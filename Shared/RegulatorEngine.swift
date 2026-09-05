import Foundation

/// Общий цикл регулятора для телефона и часов: принимает пульс, раз в интервал
/// решает, куда двигать ритм. Чистая логика без таймеров и звука.
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
    private(set) var smoothedHeartRate: Double?
    private(set) var latestHeartRate: Double?
    private(set) var lastHeartRateAt: Date?
    private var lastAdjust: Date?
    private var startedAt: Date?
    private var pausedAt: Date?

    /// Сколько секунд без свежего пульса, после чего ритм замораживаем.
    var staleAfter: TimeInterval = 15

    init(settings: RegulatorSettings) {
        self.settings = settings
        controller = CadenceController(settings: settings)
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
    }

    var cadence: Int { controller.cadence }

    /// Начало тренировки: ритм на нижнюю границу, история пульса забыта.
    mutating func reset(at now: Date = Date()) {
        controller.reset()
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
        smoothedHeartRate = nil
        latestHeartRate = nil
        lastAdjust = nil
        startedAt = now
        pausedAt = nil
    }

    mutating func ingest(bpm: Int, at time: Date) {
        lastHeartRateAt = time
        latestHeartRate = Double(bpm)
        smoothedHeartRate = smoother.add(Double(bpm), at: time)
    }

    func isHeartRateFresh(at now: Date) -> Bool {
        guard let lastHeartRateAt else { return false }
        return now.timeIntervalSince(lastHeartRateAt) <= staleAfter
    }

    /// Пульс, по которому принимается решение. Пока пульс ниже цели, это сглаженное
    /// значение. Как только сырой пульс выше цели, берём его без задержки сглаживания,
    /// чтобы спуск ритма начинался сразу, а не когда фильтр догонит.
    var decisionHeartRate: Double? {
        guard let smoothed = smoothedHeartRate else { return latestHeartRate }
        guard let latest = latestHeartRate else { return smoothed }
        let target = Double(settings.targetHeartRate)
        return latest > target ? max(smoothed, latest) : smoothed
    }

    /// Сколько секунд разминки осталось. Ноль, когда разминка закончилась или её нет.
    func warmupRemaining(at now: Date) -> TimeInterval {
        guard let startedAt, settings.warmupMinutes > 0 else { return 0 }
        let reference = pausedAt ?? now
        let elapsed = reference.timeIntervalSince(startedAt)
        return max(0, TimeInterval(settings.warmupMinutes * 60) - elapsed)
    }

    func isWarmingUp(at now: Date) -> Bool {
        warmupRemaining(at: now) > 0
    }

    mutating func markPaused(at now: Date) {
        pausedAt = now
    }

    /// После паузы: разминка не тратится на паузу, а первая подстройка случится
    /// не сразу, а через полный интервал.
    mutating func markResumed(at now: Date) {
        if let pausedAt, let startedAt {
            self.startedAt = startedAt.addingTimeInterval(now.timeIntervalSince(pausedAt))
        }
        pausedAt = nil
        lastAdjust = now
    }

    /// Вызывается раз в секунду. Возвращает решение, если подошло время подстройки.
    mutating func tick(at now: Date) -> Adjustment? {
        if lastAdjust == nil { lastAdjust = now }
        guard let lastAdjust, now.timeIntervalSince(lastAdjust) >= settings.adjustInterval else { return nil }
        self.lastAdjust = now
        guard let heartRate = decisionHeartRate, isHeartRateFresh(at: now) else { return nil }
        // На разминке ритм стоит на нижней границе и не меняется.
        if isWarmingUp(at: now) {
            return Adjustment(heartRate: heartRate, cadence: controller.cadence, action: .hold)
        }
        let action = controller.adjust(forHeartRate: heartRate)
        return Adjustment(heartRate: heartRate, cadence: controller.cadence, action: action)
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
