import Foundation

/// Экономичность пробежки: сколько движения даёт каждый удар сердца сверх покоя,
/// и не разъехались ли темп и пульс к концу.
struct EconomyReport: Codable, Equatable {
    /// Пульс покоя, от которого считались удары «сверх покоя».
    var restingHeartRate: Int
    /// Метров на удар сверх пульса покоя за всю пробежку после включения регулятора.
    var metersPerBeatAboveRest: Double?
    /// Отношение скорости к пульсу сверх покоя в первой и второй половине.
    var firstHalfRatio: Double?
    var secondHalfRatio: Double?
    /// На сколько процентов вторая половина хуже первой. Больше 5 % значит нагрузка
    /// выше аэробной или жара, обезвоживание; отрицательное значит разбежались.
    var decouplingPercent: Double?
    /// Дрейф: на сколько ударов в час растёт пульс при том же темпе. Наклон
    /// остатка пульса после вычета вклада скорости.
    var driftBeatsPerHour: Double?

    static let minimumSeconds = 1200
    /// До этого расхождение считается аэробным, нагрузка в порядке.
    static let aerobicDecoupling = 5.0
    /// Выше этого нагрузка явно выше аэробной.
    static let hardDecoupling = 10.0
}

extension RunAnalyzer {
    /// Считается по секундам после включения регулятора, без разминки и заминки.
    static func economy(rows: [TelemetryRow], restingHeartRate: Int) -> EconomyReport? {
        let rest = Double(restingHeartRate)
        let reg = rows.filter { $0.phase == .run && $0.heartRate != nil }
        var report = EconomyReport(restingHeartRate: restingHeartRate)
        guard reg.count >= EconomyReport.minimumSeconds else { return nil }

        // Метры на удар сверх покоя: дистанция за период на суммарные удары сверх покоя.
        let distance = max(0, (reg.last?.distanceMeters ?? 0) - (reg.first?.distanceMeters ?? 0))
        let beatsAboveRest = reg.reduce(0.0) { $0 + max(0, Double($1.heartRate ?? 0) - rest) / 60 }
        if distance > 200, beatsAboveRest > 0 {
            report.metersPerBeatAboveRest = distance / beatsAboveRest
        }

        // Расхождение половин по скорости и пульсу.
        let half = reg.count / 2
        func ratio(_ part: ArraySlice<TelemetryRow>) -> Double? {
            let speeds = part.compactMap(\.speedMetersPerSecond)
            let hrs = part.compactMap { $0.heartRate.map(Double.init) }
            guard speeds.count >= part.count / 2, !hrs.isEmpty else { return nil }
            let above = mean(hrs) - rest
            guard above > 5 else { return nil }
            return mean(speeds) / above
        }
        if let first = ratio(reg[0..<half]), let second = ratio(reg[half...]) {
            report.firstHalfRatio = first
            report.secondHalfRatio = second
            report.decouplingPercent = (first / second - 1) * 100
        }

        // Дрейф: пульс минус вклад скорости (через наклон пульса по скорости), наклон по времени.
        let withSpeed = reg.filter { $0.speedMetersPerSecond != nil }
        if withSpeed.count >= EconomyReport.minimumSeconds / 2 {
            let speeds = withSpeed.map { $0.speedMetersPerSecond ?? 0 }
            let hrs = withSpeed.map { Double($0.heartRate ?? 0) }
            let perSpeed = max(0, slope(speeds, hrs))
            let meanSpeed = mean(speeds)
            let residual = zip(hrs, speeds).map { $0 - perSpeed * ($1 - meanSpeed) }
            let hours = withSpeed.map { $0.elapsed / 3600 }
            report.driftBeatsPerHour = slope(hours, residual)
        }
        return report
    }
}

/// Пульсовые зоны по Карвонену: от резерва между покоем и максимумом (220 минус возраст).
enum HeartRateZones {
    struct Suggestion: Equatable {
        var maxHeartRate: Int
        var zone2Low: Int
        var zone2High: Int
        /// Цель для регулятора: верх второй зоны.
        var target: Int
        /// Нижняя граница зоны для регулятора: низ второй зоны.
        var lower: Int
    }

    static func karvonen(age: Int, restingHeartRate: Int) -> Suggestion {
        let maxHR = max(120, 220 - age)
        let reserve = Double(max(20, maxHR - restingHeartRate))
        let low = Int((Double(restingHeartRate) + 0.60 * reserve).rounded())
        let high = Int((Double(restingHeartRate) + 0.70 * reserve).rounded())
        let target = Int((Double(high) / 5).rounded()) * 5
        return Suggestion(maxHeartRate: maxHR, zone2Low: low, zone2High: high, target: target, lower: max(40, target - (high - low) - 5))
    }
}
