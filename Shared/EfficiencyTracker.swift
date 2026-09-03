import Foundation

/// Эффективность бега: метров на один удар сердца. Считает итог за тренировку
/// и скользящее значение за последние сто метров.
struct EfficiencyTracker {
    private struct Point {
        let time: Date
        let distance: Double
        let beats: Double
    }

    private var points: [Point] = []
    private var beats = 0.0
    private var lastTime: Date?
    private var lastHeartRate: Double?
    private var lastDistance = 0.0

    /// Окно для скользящего значения, метров.
    var windowMeters = 100.0

    mutating func reset() {
        points.removeAll()
        beats = 0
        lastTime = nil
        lastHeartRate = nil
        lastDistance = 0
    }

    /// Вызывается раз в секунду с накопленной дистанцией и текущим пульсом.
    mutating func update(time: Date, distance: Double, heartRate: Double?) {
        if let lastTime, let lastHeartRate {
            let dt = max(0, time.timeIntervalSince(lastTime))
            beats += lastHeartRate / 60 * dt
        }
        lastTime = time
        if let heartRate { lastHeartRate = heartRate }
        lastDistance = max(lastDistance, distance)
        points.append(Point(time: time, distance: lastDistance, beats: beats))
        // Держим историю с запасом на два окна, чтобы искать начало окна.
        while points.count > 2, points[1].distance < lastDistance - windowMeters * 2 {
            points.removeFirst()
        }
    }

    /// Метров на удар за всю тренировку.
    var total: Double? {
        guard beats > 30, lastDistance > 50 else { return nil }
        return lastDistance / beats
    }

    /// Метров на удар за последнее окно. Nil, пока окно не набралось.
    var recent: Double? {
        guard let last = points.last else { return nil }
        let threshold = last.distance - windowMeters
        guard let start = points.last(where: { $0.distance <= threshold }) else { return nil }
        let dBeats = last.beats - start.beats
        let dDistance = last.distance - start.distance
        guard dBeats > 5, dDistance > 20 else { return nil }
        return dDistance / dBeats
    }
}
