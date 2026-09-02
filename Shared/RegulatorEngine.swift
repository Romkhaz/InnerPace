import Foundation

/// Общий цикл регулятора для телефона и часов: принимает пульс, раз в интервал
/// решает, куда двигать каденс. Чистая логика без таймеров и звука.
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
    private(set) var lastHeartRateAt: Date?
    private var lastAdjust: Date?

    /// Сколько секунд без свежего пульса, после чего каденс замораживаем.
    var staleAfter: TimeInterval = 15

    init(settings: RegulatorSettings) {
        self.settings = settings
        controller = CadenceController(settings: settings)
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
    }

    var cadence: Int { controller.cadence }

    /// Начало тренировки: каденс на нижнюю границу, история пульса забыта.
    mutating func reset() {
        controller.reset()
        smoother = HeartRateSmoother(timeConstant: settings.smoothingSeconds)
        smoothedHeartRate = nil
        lastAdjust = nil
    }

    mutating func ingest(bpm: Int, at time: Date) {
        lastHeartRateAt = time
        smoothedHeartRate = smoother.add(Double(bpm), at: time)
    }

    func isHeartRateFresh(at now: Date) -> Bool {
        guard let lastHeartRateAt else { return false }
        return now.timeIntervalSince(lastHeartRateAt) <= staleAfter
    }

    /// После паузы: первая подстройка случится не сразу, а через полный интервал.
    mutating func markResumed(at now: Date) {
        lastAdjust = now
    }

    /// Вызывается раз в секунду. Возвращает решение, если подошло время подстройки.
    mutating func tick(at now: Date) -> Adjustment? {
        if lastAdjust == nil { lastAdjust = now }
        guard let lastAdjust, now.timeIntervalSince(lastAdjust) >= settings.adjustInterval else { return nil }
        self.lastAdjust = now
        guard let heartRate = smoothedHeartRate, isHeartRateFresh(at: now) else { return nil }
        let action = controller.adjust(forHeartRate: heartRate)
        return Adjustment(heartRate: heartRate, cadence: controller.cadence, action: action)
    }
}

extension RegulatorEngine.Adjustment {
    /// Строка для журнала, nil если каденс не менялся.
    var logLine: String? {
        let hr = Int(heartRate.rounded())
        switch action {
        case .speedUp(let delta): return "Пульс \(hr) → каденс \(cadence) (+\(delta))"
        case .slowDown(let delta): return "Пульс \(hr) → каденс \(cadence) (−\(delta))"
        case .hold: return nil
        }
    }
}
