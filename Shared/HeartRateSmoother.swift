import Foundation

/// Экспоненциальное сглаживание пульса. Пульс приходит нерегулярно,
/// поэтому коэффициент считается от реального интервала между отсчётами.
struct HeartRateSmoother {
    var timeConstant: TimeInterval
    private(set) var value: Double?
    private var lastTimestamp: Date?

    init(timeConstant: TimeInterval) {
        self.timeConstant = timeConstant
    }

    @discardableResult
    mutating func add(_ bpm: Double, at time: Date = Date()) -> Double {
        guard let previous = value, let last = lastTimestamp else {
            value = bpm
            lastTimestamp = time
            return bpm
        }
        let dt = max(0, time.timeIntervalSince(last))
        let alpha = timeConstant <= 0 ? 1.0 : 1.0 - exp(-dt / timeConstant)
        let next = previous + alpha * (bpm - previous)
        value = next
        lastTimestamp = time
        return next
    }

    mutating func reset() {
        value = nil
        lastTimestamp = nil
    }
}
