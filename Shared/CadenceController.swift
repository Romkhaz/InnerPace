import Foundation

/// Регулятор: по сглаженному пульсу решает, куда двигать ритм.
///
/// Цель регулятора — целевой пульс. Зоны снизу вверх:
/// - далеко ниже цели: ритм растёт, шаг пропорционален расстоянию до цели;
/// - зона подхода (за `approachPercent` до цели): ритм растёт по одному шагу
///   за интервал, чтобы инерция пульса не вынесла его за цель;
/// - полоса удержания (`holdBand` под целью): ритм не меняется;
/// - выше цели: ритм падает, в `slowdownFactor` раз быстрее, чем рос.
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

    mutating func setCadence(_ value: Int) {
        cadence = clamp(value)
    }

    /// Вызывается раз в `adjustInterval` секунд.
    mutating func adjust(forHeartRate heartRate: Double) -> Action {
        let target = Double(settings.targetHeartRate)
        let zoneWidth = max(1, target - Double(settings.heartRateMin))
        let gain = Double(settings.maxStep) / zoneWidth

        if heartRate > target {
            let factor = min(3, max(1, settings.slowdownFactor))
            let maxDown = max(1, Int((Double(settings.maxStep) * factor).rounded()))
            let raw = (heartRate - target) * gain * factor
            let step = min(maxDown, max(1, Int(raw.rounded())))
            return move(by: -step)
        }
        if heartRate >= settings.holdHeartRate {
            return .hold
        }
        if heartRate >= settings.approachHeartRate {
            return move(by: 1)
        }
        let raw = (target - heartRate) * gain
        let step = min(settings.maxStep, max(1, Int(raw.rounded())))
        return move(by: step)
    }

    private mutating func move(by delta: Int) -> Action {
        let next = clamp(cadence + delta)
        let applied = next - cadence
        cadence = next
        if applied > 0 { return .speedUp(applied) }
        if applied < 0 { return .slowDown(-applied) }
        return .hold
    }

    private func clamp(_ value: Int) -> Int {
        min(settings.cadenceMax, max(settings.cadenceMin, value))
    }
}
