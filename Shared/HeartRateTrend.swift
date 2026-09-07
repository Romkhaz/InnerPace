import Foundation

/// Тренд пульса: наклон прямой, подогнанной по последним `window` секундам
/// сглаженного пульса, в ударах в минуту за минуту. Нужен, чтобы регулятор
/// смотрел не туда, где пульс сейчас, а туда, куда он придёт через задержку
/// отклика организма на смену ритма.
struct HeartRateTrend {
    var window: TimeInterval
    private var samples: [(time: Date, value: Double)] = []

    init(window: TimeInterval = 20) {
        self.window = window
    }

    mutating func add(_ value: Double, at time: Date) {
        samples.append((time, value))
        let cutoff = time.addingTimeInterval(-window)
        samples.removeAll { $0.time < cutoff }
    }

    mutating func reset() {
        samples.removeAll()
    }

    /// Наклон в ударах в минуту за минуту. Нет данных хотя бы за половину окна, значит ноль.
    var slopePerMinute: Double {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return 0 }
        let span = last.time.timeIntervalSince(first.time)
        guard span >= window / 2 else { return 0 }
        let n = Double(samples.count)
        let t0 = first.time
        let xs = samples.map { $0.time.timeIntervalSince(t0) }
        let ys = samples.map { $0.value }
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0 else { return 0 }
        return num / den * 60
    }
}
