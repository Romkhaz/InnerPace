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
    struct Adjustment: Equatable {
        let heartRate: Double
        let cadence: Int
        let action: CadenceController.Action
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
    private(set) var lastHeartRateAt: Date?
    private(set) var isRegulating = false
    private(set) var isOverLimit = false
    private var overLimitSince: Date?
    private var armingSince: Date?
    private var lastAdjust: Date?

    /// Сколько секунд без свежего пульса, после чего ритм замораживаем.
    var staleAfter: TimeInterval = 15
    /// Сколько секунд пульс должен держаться выше цели при ритме на нижней границе,
    /// прежде чем объявить предел. Отсекает секундные всплески.
    var overLimitDelay: TimeInterval = 10
    /// На сколько ударов пульс должен опуститься ниже цели, чтобы предел снялся.
    var overLimitHysteresis: Double = 2
    /// Если пульс падает быстрее этого (ударов в минуту за минуту), предел не объявляем:
    /// он сам уйдёт под цель, подсказка «сбавь» только сбила бы с толку.
    var overLimitFallingSlope: Double = -2

    init(settings: RegulatorSettings) {
        self.settings = settings
        controller = CadenceController(settings: settings)
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
    }

    var cadence: Int { controller.cadence }

    /// Начало тренировки: ритм на нижнюю границу, история пульса забыта, регулятор ждёт пульса.
    mutating func reset(at now: Date = Date()) {
        controller.reset()
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
        trend.reset()
        smoothedHeartRate = nil
        latestHeartRate = nil
        lastAdjust = nil
        isRegulating = false
        isOverLimit = false
        overLimitSince = nil
        armingSince = nil
    }

    mutating func ingest(bpm: Int, at time: Date) {
        lastHeartRateAt = time
        latestHeartRate = Double(bpm)
        let smoothed = smoother.add(Double(bpm), at: time)
        smoothedHeartRate = smoothed
        trend.add(smoothed, at: time)
    }

    /// Тренд сглаженного пульса, ударов в минуту за минуту.
    var trendPerMinute: Double { trend.slopePerMinute }

    /// Сглаженный пульс плюс тренд на `predictSeconds` вперёд.
    var predictedHeartRate: Double? {
        guard let smoothed = smoothedHeartRate else { return nil }
        return smoothed + trendPerMinute * Double(settings.predictSeconds) / 60
    }

    func isHeartRateFresh(at now: Date) -> Bool {
        guard let lastHeartRateAt else { return false }
        return now.timeIntervalSince(lastHeartRateAt) <= staleAfter
    }

    /// Пульс, по которому принимается решение: прогноз по тренду. Как только сырой
    /// пульс выше цели, берём его, если он выше прогноза, без задержки сглаживания,
    /// чтобы спуск ритма начинался сразу, а не когда фильтр догонит.
    var decisionHeartRate: Double? {
        guard let predicted = predictedHeartRate else { return latestHeartRate }
        guard let latest = latestHeartRate else { return predicted }
        let target = Double(settings.targetHeartRate)
        return latest > target ? max(predicted, latest) : predicted
    }

    mutating func markPaused(at now: Date) {}

    /// После паузы первая подстройка случится не сразу, а через полный интервал.
    mutating func markResumed(at now: Date) {
        lastAdjust = now
    }

    /// Вызывается раз в секунду. Возвращает решение, если подошло время подстройки.
    mutating func tick(at now: Date) -> Adjustment? {
        updateArming(at: now)
        updateOverLimit(at: now)
        if lastAdjust == nil { lastAdjust = now }
        guard let lastAdjust, now.timeIntervalSince(lastAdjust) >= settings.adjustInterval else { return nil }
        self.lastAdjust = now
        guard let heartRate = decisionHeartRate, isHeartRateFresh(at: now) else { return nil }
        guard isRegulating else {
            return Adjustment(heartRate: heartRate, cadence: controller.cadence, action: .hold)
        }
        let action = controller.adjust(forHeartRate: heartRate)
        updateOverLimit(at: now)
        return Adjustment(heartRate: heartRate, cadence: controller.cadence, action: action)
    }

    /// Регулятор включается, когда сглаженный пульс продержался в зоне подхода
    /// (от `approachHeartRate`) не меньше `armSeconds` подряд.
    private mutating func updateArming(at now: Date) {
        guard !isRegulating else { return }
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
        let target = Double(settings.targetHeartRate)
        guard isRegulating, isHeartRateFresh(at: now), let heartRate = smoothedHeartRate else {
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
    /// Строка для журнала, nil если ритм не менялся.
    var logLine: String? {
        let hr = Int(heartRate.rounded())
        switch action {
        case .speedUp(let delta): return String(localized: "Пульс \(hr) → ритм \(cadence) (+\(delta))")
        case .slowDown(let delta): return String(localized: "Пульс \(hr) → ритм \(cadence) (−\(delta))")
        case .hold: return nil
        }
    }
}
