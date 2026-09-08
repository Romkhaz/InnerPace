import Foundation

/// Общий цикл регулятора для телефона и часов: принимает пульс, раз в интервал
/// решает, куда двигать ритм. Чистая логика без таймеров и звука.
///
/// Старт всегда с нижней границы ритма. Регулятор включается, когда пульс
/// продержался в зоне подхода не меньше `armSeconds`, то есть сердце вошло
/// в рабочий режим, и дальше работает до конца тренировки.
///
/// Пульс отвечает на смену ритма с задержкой около минуты, поэтому решение
/// принимается не по текущему пульсу, а по прогнозу: сглаженный пульс плюс тренд
/// на `predictSeconds` вперёд. Так ритм перестаёт расти раньше, чем пульс упрётся
/// в цель, и перестаёт падать, когда пульс уже идёт вниз.
///
/// Если ритм уже упёрся в нижнюю границу, а пульс всё равно выше цели дольше
/// `overLimitDelay` и не падает, включается состояние «предел»: снижать ритм
/// больше нечего, нужно сбавлять усилие. Состояние снимается, когда пульс
/// вернулся под цель.
struct RegulatorEngine {
    enum ProbePhase: Equatable {
        case started, finished, aborted
    }

    enum Event: Equatable {
        case warmupEnded, cooldownStarted, cooldownStep
    }

    struct Adjustment: Equatable {
        /// Пульс, по которому принято решение: прогноз или сырой выше цели.
        let heartRate: Double
        /// Сглаженный измеренный пульс на момент решения.
        let measuredHeartRate: Double
        let cadence: Int
        let action: CadenceController.Action
        /// Если решение относится к пробе отклика, её фаза.
        var probe: ProbePhase? = nil
        /// Остановка: регулятор начал заново, как в начале тренировки.
        var restarted = false
        var event: Event? = nil
    }

    var settings: RegulatorSettings {
        didSet {
            guard settings != oldValue else { return }
            controller.settings = settings
            smoother.timeConstant = settings.smoothingSeconds
        }
    }

    private var controller: CadenceController
    private var smoother: HeartRateSmoother
    private var trend = HeartRateTrend()
    private(set) var smoothedHeartRate: Double?
    private(set) var latestHeartRate: Double?
    private var previousHeartRate: Double?
    private var stoppedSince: Date?
    private var pendingRestart = false
    private(set) var lastHeartRateAt: Date?
    private(set) var isRegulating = false
    private(set) var isOverLimit = false
    /// Проба отклика: разрешена ли в этой тренировке. Ставится моделью на старте.
    var probeEnabled = false
    private(set) var isProbing = false
    private(set) var isCoolingDown = false
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var warmupAnnounced = false
    private var lastCooldownStep: Date?
    private var probeDone = false
    private var probeStartedAt: Date?
    private var probeRestoreCadence = 0
    private var inBandSince: Date?
    private var overLimitSince: Date?
    private var armingSince: Date?
    private var lastAdjust: Date?

    /// Сколько секунд без свежего пульса, после чего ритм замораживаем.
    var staleAfter: TimeInterval = 15
    /// Фактический каденс ниже этого считается остановкой или ходьбой.
    var stopCadence = 120
    /// Сколько секунд такого каденса, чтобы регулятор начал заново, как в начале тренировки.
    var stopAfter: TimeInterval = 10
    /// Сколько секунд пульс должен держаться выше цели при ритме на нижней границе,
    /// прежде чем объявить предел. Отсекает секундные всплески.
    var overLimitDelay: TimeInterval = 10
    /// На сколько ударов пульс должен опуститься ниже цели, чтобы предел снялся.
    var overLimitHysteresis: Double = 2
    /// Быстрее этого (ударов в минуту за минуту) тренд в прогноз не берём: за 20 с окна
    /// подъём в гору даёт наклон 40–50, и экстраполяция на минуту вперёд выносила решение
    /// далеко за реальный пульс. Сам тренд в телеметрии остаётся неограниченным.
    var maxTrendPerMinute: Double = 15
    /// Если пульс падает быстрее этого (ударов в минуту за минуту), предел не объявляем:
    /// он сам уйдёт под цель, подсказка «сбавь» только сбила бы с толку.
    var overLimitFallingSlope: Double = -2

    init(settings: RegulatorSettings) {
        self.settings = settings
        controller = CadenceController(settings: settings)
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
    }

    var cadence: Int { controller.cadence }

    /// Время тренировки без пауз.
    func activeSeconds(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - pausedNow)
    }

    func isWarmingUp(at now: Date) -> Bool {
        settings.warmupSeconds > 0 && activeSeconds(at: now) < TimeInterval(settings.warmupSeconds)
    }

    /// Фаза для телеметрии и интерфейса.
    func phase(at now: Date) -> RunPhase {
        if isCoolingDown { return .cooldown }
        if isProbing { return .probe }
        if isRegulating { return .run }
        return isWarmingUp(at: now) ? .warmup : .waiting
    }

    /// Заминка: регулятор выключается, ритм плавно снижается до нижней границы минус `cooldownDrop`.
    mutating func beginCooldown(at now: Date) -> Adjustment? {
        guard !isCoolingDown else { return nil }
        if isProbing { cancelProbe() }
        isCoolingDown = true
        isRegulating = false
        isOverLimit = false
        overLimitSince = nil
        armingSince = nil
        lastCooldownStep = now
        let decided = decisionHeartRate ?? 0
        return Adjustment(heartRate: decided, measuredHeartRate: smoothedHeartRate ?? decided, cadence: controller.cadence,
                          action: .hold, event: .cooldownStarted)
    }

    var cooldownFloor: Int { max(100, settings.cadenceMin - RegulatorSettings.cooldownDrop) }

    /// Начало тренировки: ритм на нижнюю границу, история пульса забыта, регулятор ждёт пульса.
    mutating func reset(at now: Date = Date()) {
        startedAt = now
        pausedAt = nil
        pausedTotal = 0
        warmupAnnounced = settings.warmupSeconds == 0
        isCoolingDown = false
        lastCooldownStep = nil
        controller.reset()
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
        trend.reset()
        smoothedHeartRate = nil
        latestHeartRate = nil
        previousHeartRate = nil
        stoppedSince = nil
        pendingRestart = false
        lastAdjust = nil
        isRegulating = false
        isOverLimit = false
        overLimitSince = nil
        armingSince = nil
        isProbing = false
        probeDone = false
        probeStartedAt = nil
        inBandSince = nil
    }

    mutating func ingest(bpm: Int, at time: Date) {
        lastHeartRateAt = time
        previousHeartRate = latestHeartRate
        latestHeartRate = Double(bpm)
        let smoothed = smoother.add(Double(bpm), at: time)
        smoothedHeartRate = smoothed
        trend.add(smoothed, at: time)
    }

    /// Тренд сглаженного пульса, ударов в минуту за минуту.
    var trendPerMinute: Double { trend.slopePerMinute }

    /// Сглаженный пульс плюс ограниченный тренд на `predictSeconds` вперёд.
    var predictedHeartRate: Double? {
        guard let smoothed = smoothedHeartRate else { return nil }
        let slope = min(maxTrendPerMinute, max(-maxTrendPerMinute, trendPerMinute))
        return smoothed + slope * Double(settings.predictSeconds) / 60
    }

    func isHeartRateFresh(at now: Date) -> Bool {
        guard let lastHeartRateAt else { return false }
        return now.timeIntervalSince(lastHeartRateAt) <= staleAfter
    }

    /// Пульс, по которому принимается решение: прогноз по тренду. Как только сырой
    /// пульс два отсчёта подряд выше цели, берём его, если он выше прогноза, без задержки
    /// сглаживания, чтобы спуск ритма начинался сразу. Один отсчёт не считается:
    /// оптический датчик даёт одиночные выбросы.
    var decisionHeartRate: Double? {
        guard let predicted = predictedHeartRate else { return latestHeartRate }
        guard let latest = latestHeartRate else { return predicted }
        let target = Double(settings.targetHeartRate)
        let confirmedAbove = latest > target && (previousHeartRate ?? 0) > target
        return confirmedAbove ? max(predicted, latest) : predicted
    }

    /// Фактический каденс с шагомера. Ниже `stopCadence` дольше `stopAfter` секунд
    /// значит остановка: на следующем такте регулятор начнёт заново.
    mutating func noteActualCadence(_ spm: Int?, at now: Date) {
        guard let spm, spm < stopCadence else {
            stoppedSince = nil
            return
        }
        if stoppedSince == nil { stoppedSince = now }
        if let since = stoppedSince, now.timeIntervalSince(since) >= stopAfter,
           isRegulating || controller.cadence > settings.cadenceMin {
            pendingRestart = true
        }
    }

    /// Начать заново после остановки: ритм на нижнюю границу, ждать включения, как на старте.
    private mutating func restart(at now: Date) -> Adjustment {
        let before = controller.cadence
        if isProbing { cancelProbe() }
        controller.reset()
        isRegulating = false
        armingSince = nil
        isOverLimit = false
        overLimitSince = nil
        pendingRestart = false
        stoppedSince = now
        lastAdjust = now
        let decided = decisionHeartRate ?? 0
        let delta = before - controller.cadence
        return Adjustment(heartRate: decided, measuredHeartRate: smoothedHeartRate ?? decided, cadence: controller.cadence,
                          action: delta > 0 ? .slowDown(delta) : .hold, restarted: true)
    }

    private mutating func cancelProbe() {
        controller.setCadence(probeRestoreCadence)
        isProbing = false
        probeStartedAt = nil
        probeDone = false
    }

    /// Пауза отменяет пробу: её окно уже испорчено. Возвращает true, если проба была отменена.
    @discardableResult
    mutating func markPaused(at now: Date) -> Bool {
        if pausedAt == nil { pausedAt = now }
        guard isProbing else { return false }
        cancelProbe()
        return true
    }

    /// После паузы первая подстройка случится не сразу, а через полный интервал.
    mutating func markResumed(at now: Date) {
        if let pausedAt { pausedTotal += now.timeIntervalSince(pausedAt) }
        pausedAt = nil
        lastAdjust = now
    }

    /// Вызывается раз в секунду. Возвращает решение, если подошло время подстройки.
    mutating func tick(at now: Date) -> Adjustment? {
        updateArming(at: now)
        updateOverLimit(at: now)
        if lastAdjust == nil { lastAdjust = now }
        if isCoolingDown { return cooldownStep(at: now) }
        if !warmupAnnounced, !isWarmingUp(at: now) {
            warmupAnnounced = true
            let decided = decisionHeartRate ?? 0
            return Adjustment(heartRate: decided, measuredHeartRate: smoothedHeartRate ?? decided, cadence: controller.cadence,
                              action: .hold, event: .warmupEnded)
        }
        if pendingRestart { return restart(at: now) }
        if let probe = updateProbe(at: now) { return probe }
        if isProbing { return nil }
        guard let lastAdjust, now.timeIntervalSince(lastAdjust) >= settings.adjustInterval else { return nil }
        self.lastAdjust = now
        guard let heartRate = decisionHeartRate, isHeartRateFresh(at: now) else { return nil }
        let measured = smoothedHeartRate ?? heartRate
        guard isRegulating else {
            return Adjustment(heartRate: heartRate, measuredHeartRate: measured, cadence: controller.cadence, action: .hold)
        }
        let action = controller.adjust(forHeartRate: heartRate)
        updateOverLimit(at: now)
        return Adjustment(heartRate: heartRate, measuredHeartRate: measured, cadence: controller.cadence, action: action)
    }

    private mutating func cooldownStep(at now: Date) -> Adjustment? {
        guard controller.cadence > cooldownFloor,
              let last = lastCooldownStep, now.timeIntervalSince(last) >= RegulatorSettings.cooldownStepSeconds else { return nil }
        lastCooldownStep = now
        // Контроллер зажат нижней границей, поэтому ниже неё ставим напрямую.
        let next = controller.cadence - 1
        controller.setCadence(max(settings.cadenceMin, next))
        if next < settings.cadenceMin { controller.forceCadence(next) }
        let decided = decisionHeartRate ?? 0
        return Adjustment(heartRate: decided, measuredHeartRate: smoothedHeartRate ?? decided, cadence: controller.cadence,
                          action: .slowDown(1), event: .cooldownStep)
    }

    /// Проба отклика: когда пульс минуту ровно держится в полосе удержания, ритм поднимается
    /// на `probeStep` на `probeSeconds`, регулятор на это время замирает, потом ритм возвращается.
    /// Один раз за тренировку. Прерывается, если сырой пульс ушёл выше цели больше чем на 5.
    private mutating func updateProbe(at now: Date) -> Adjustment? {
        let target = Double(settings.targetHeartRate)
        if isProbing, let started = probeStartedAt {
            let aborted = (latestHeartRate ?? 0) > target + 5
            guard aborted || now.timeIntervalSince(started) >= RegulatorSettings.probeSeconds else { return nil }
            let before = controller.cadence
            controller.setCadence(probeRestoreCadence)
            isProbing = false
            probeStartedAt = nil
            lastAdjust = now
            let decided = decisionHeartRate ?? 0
            return Adjustment(heartRate: decided, measuredHeartRate: smoothedHeartRate ?? decided, cadence: controller.cadence,
                              action: .slowDown(before - controller.cadence), probe: aborted ? .aborted : .finished)
        }
        guard probeEnabled, !probeDone, isRegulating, !isOverLimit, isHeartRateFresh(at: now),
              let smoothed = smoothedHeartRate, smoothed >= settings.holdHeartRate, smoothed <= target,
              abs(trendPerMinute) < 3 else {
            inBandSince = nil
            return nil
        }
        if inBandSince == nil { inBandSince = now }
        guard let since = inBandSince, now.timeIntervalSince(since) >= RegulatorSettings.probeReadySeconds,
              controller.cadence + RegulatorSettings.probeStep <= settings.cadenceMax else { return nil }
        probeRestoreCadence = controller.cadence
        controller.setCadence(controller.cadence + RegulatorSettings.probeStep)
        isProbing = true
        probeDone = true
        probeStartedAt = now
        inBandSince = nil
        lastAdjust = now
        let decided = decisionHeartRate ?? smoothed
        return Adjustment(heartRate: decided, measuredHeartRate: smoothed, cadence: controller.cadence,
                          action: .speedUp(RegulatorSettings.probeStep), probe: .started)
    }

    /// Регулятор включается, когда сглаженный пульс продержался в зоне подхода
    /// (от `approachHeartRate`) не меньше `armSeconds` подряд.
    private mutating func updateArming(at now: Date) {
        guard !isRegulating, !isCoolingDown, !isWarmingUp(at: now) else { return }
        guard isHeartRateFresh(at: now), let heartRate = smoothedHeartRate,
              heartRate >= settings.approachHeartRate else {
            armingSince = nil
            return
        }
        if armingSince == nil { armingSince = now }
        if let since = armingSince, now.timeIntervalSince(since) >= TimeInterval(settings.armSeconds) {
            isRegulating = true
        }
    }

    /// Предел считается по сглаженному пульсу без прогноза: прогноз нужен, чтобы
    /// заранее двигать ритм, а предел объявляется по факту.
    private mutating func updateOverLimit(at now: Date) {
        let warming = isWarmingUp(at: now)
        let target = Double(settings.targetHeartRate) - (warming ? Double(RegulatorSettings.warmupMargin) : 0)
        guard isRegulating || warming, !isCoolingDown, isHeartRateFresh(at: now), let heartRate = smoothedHeartRate else {
            overLimitSince = nil
            isOverLimit = false
            return
        }
        let atFloor = controller.cadence <= settings.cadenceMin
        if isOverLimit {
            // Снимаем предел, когда пульс ушёл под цель с запасом или ритм снова есть куда снижать.
            if heartRate <= target - overLimitHysteresis || !atFloor {
                isOverLimit = false
                overLimitSince = nil
            }
            return
        }
        if atFloor, heartRate > target, trendPerMinute > overLimitFallingSlope {
            if overLimitSince == nil { overLimitSince = now }
            if let since = overLimitSince, now.timeIntervalSince(since) >= overLimitDelay {
                isOverLimit = true
            }
        } else {
            overLimitSince = nil
        }
    }
}

extension RegulatorEngine.Adjustment {
    /// Строка для журнала, nil если ритм не менялся. Показывает измеренный пульс и,
    /// если решение принято по другому значению (прогноз или сырой), его тоже.
    var logLine: String? {
        let measured = Int(measuredHeartRate.rounded())
        let decided = Int(heartRate.rounded())
        if restarted { return String(localized: "Остановка: ритм \(cadence), регулятор ждёт пульса") }
        switch event {
        case .warmupEnded: return String(localized: "Разминка окончена, регулятор включится по пульсу")
        case .cooldownStarted: return String(localized: "Заминка: ритм плавно вниз")
        case .cooldownStep: return nil
        case nil: break
        }
        switch probe {
        case .started: return String(localized: "Проба отклика: ритм \(cadence) на \(Int(RegulatorSettings.probeSeconds)) с")
        case .finished: return String(localized: "Проба окончена: ритм \(cadence)")
        case .aborted: return String(localized: "Проба прервана, пульс \(measured): ритм \(cadence)")
        case nil: break
        }
        let pulse = decided == measured
            ? String(localized: "Пульс \(measured)")
            : String(localized: "Пульс \(measured), прогноз \(decided)")
        switch action {
        case .speedUp(let delta): return String(localized: "\(pulse) → ритм \(cadence) (+\(delta))")
        case .slowDown(let delta): return String(localized: "\(pulse) → ритм \(cadence) (−\(delta))")
        case .hold: return nil
        }
    }
}
