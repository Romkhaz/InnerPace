import Foundation

/// Положение пульса относительно зоны, для подсветки.
enum HeartRateZone {
    case unknown, below, inside, above

    init(heartRate: Double, settings: RegulatorSettings) {
        if heartRate < Double(settings.heartRateMin) { self = .below }
        else if heartRate > Double(settings.heartRateMax) { self = .above }
        else { self = .inside }
    }
}
