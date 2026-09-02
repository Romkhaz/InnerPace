import Foundation

/// Регулятор: по сглаженному пульсу решает, куда двигать каденс.
///
/// Цель регулятора — верхняя граница зоны пульса. Пока пульс ниже цели,
/// каденс растёт, пока выше — падает. Шаг пропорционален расстоянию до цели:
/// на нижней границе зоны шаг максимальный, рядом с целью — один удар в минуту.
/// Прямо под целью есть полоса удержания, в ней каденс не трогаем,
/// чтобы система не дёргалась из-за запаздывания пульса.
struct CadenceController {
    enum Action: Equatable {
        case speedUp(Int)
        case slowDown(Int)
        case hold
    }

    var settings: RegulatorSettings {
        didSet { cadence = clamp(cadence) }
    }
    private(set) var cadence: Int

    init(settings: RegulatorSettings) {
        self.settings = settings
        self.cadence = settings.cadenceMin
    }

    mutating func reset() {
        cadence = settings.cadenceMin
    }

    /// Вызывается раз в `adjustInterval` секунд.
    mutating func adjust(forHeartRate heartRate: Double) -> Action {
        let target = Double(settings.targetHeartRate)
        let zoneWidth = max(1, Double(settings.heartRateMax - settings.heartRateMin))
        let gain = Double(settings.maxStep) / zoneWidth
        let error = target - heartRate

        if error > 0 {
            if error <= Double(settings.holdBand) { return .hold }
            let step = clampedStep(error * gain)
            let next = clamp(cadence + step)
            let delta = next - cadence
            cadence = next
            return delta > 0 ? .speedUp(delta) : .hold
        }
        if error < 0 {
            let step = clampedStep(-error * gain)
            let next = clamp(cadence - step)
            let delta = cadence - next
            cadence = next
            return delta > 0 ? .slowDown(delta) : .hold
        }
        return .hold
    }

    private func clampedStep(_ raw: Double) -> Int {
        min(settings.maxStep, max(1, Int(raw.rounded())))
    }

    private func clamp(_ value: Int) -> Int {
        min(settings.cadenceMax, max(settings.cadenceMin, value))
    }
}
