import Foundation

/// Параметры регулятора каденса по пульсу.
struct RegulatorSettings: Codable, Equatable {
    /// Нижняя граница каденса, шагов в минуту. Основная настройка.
    var cadenceMin: Int = 180
    /// Верхняя граница каденса. По умолчанию считается от нижней плюс `cadenceSpanPercent`.
    var cadenceMax: Int = 207
    /// На сколько процентов верхняя граница каденса выше нижней, когда считается автоматически.
    var cadenceSpanPercent: Int = 15
    /// Нижняя граница зоны пульса. Задаёт масштаб шага регулятора и подсветку.
    var heartRateMin: Int = 130
    /// Целевой пульс. Основная настройка: регулятор ведёт пульс к этому значению.
    var heartRateMax: Int = 150
    /// За сколько процентов до цели рост ритма замедляется до одного шага за интервал.
    var approachPercent: Int = 10
    /// Полоса под целевым пульсом, внутри которой ритм не растёт.
    var holdBand: Int = 8
    /// Во сколько раз ритм падает быстрее, чем растёт. От 1 до 3.
    var slowdownFactor: Double = 2
    /// Первые минуты забега ритм держится на середине диапазона и не разгоняется.
    var warmupMinutes: Int = 3
    /// Сколько секунд между двумя подстройками ритма.
    var adjustInterval: TimeInterval = 5
    /// Максимальное изменение ритма за одну подстройку при разгоне.
    var maxStep: Int = 4
    /// Постоянная времени сглаживания пульса, секунды.
    var smoothingSeconds: Double = 10
    /// Щёлкать на каждый второй шаг.
    var halfTimeClick: Bool = false
    /// Громкость щелчка, от 0 до 1.
    var clickVolume: Double = 0.8

    static let `default` = RegulatorSettings()

    init() {}

    /// Ключи могут отсутствовать в старых сохранённых настройках, поэтому каждый читаем с запасным значением.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RegulatorSettings()
        cadenceMin = try c.decodeIfPresent(Int.self, forKey: .cadenceMin) ?? d.cadenceMin
        cadenceSpanPercent = try c.decodeIfPresent(Int.self, forKey: .cadenceSpanPercent) ?? d.cadenceSpanPercent
        cadenceMax = try c.decodeIfPresent(Int.self, forKey: .cadenceMax)
            ?? RegulatorSettings.derivedCadenceMax(from: cadenceMin, spanPercent: cadenceSpanPercent)
        heartRateMin = try c.decodeIfPresent(Int.self, forKey: .heartRateMin) ?? d.heartRateMin
        heartRateMax = try c.decodeIfPresent(Int.self, forKey: .heartRateMax) ?? d.heartRateMax
        approachPercent = try c.decodeIfPresent(Int.self, forKey: .approachPercent) ?? d.approachPercent
        holdBand = try c.decodeIfPresent(Int.self, forKey: .holdBand) ?? d.holdBand
        slowdownFactor = try c.decodeIfPresent(Double.self, forKey: .slowdownFactor) ?? d.slowdownFactor
        warmupMinutes = try c.decodeIfPresent(Int.self, forKey: .warmupMinutes) ?? d.warmupMinutes
        adjustInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .adjustInterval) ?? d.adjustInterval
        maxStep = try c.decodeIfPresent(Int.self, forKey: .maxStep) ?? d.maxStep
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? d.smoothingSeconds
        halfTimeClick = try c.decodeIfPresent(Bool.self, forKey: .halfTimeClick) ?? d.halfTimeClick
        clickVolume = try c.decodeIfPresent(Double.self, forKey: .clickVolume) ?? d.clickVolume
    }

    var targetHeartRate: Int { heartRateMax }
    var isValid: Bool { cadenceMin < cadenceMax && heartRateMin < heartRateMax }

    /// Середина диапазона каденса, с неё начинается разминка.
    var midCadence: Int { (cadenceMin + cadenceMax) / 2 }

    /// Пульс, с которого рост ритма замедляется.
    var approachHeartRate: Double {
        Double(heartRateMax) * (1 - Double(approachPercent) / 100)
    }

    /// Пульс, с которого ритм больше не растёт.
    var holdHeartRate: Double {
        Double(heartRateMax - holdBand)
    }

    static func derivedCadenceMax(from cadenceMin: Int, spanPercent: Int) -> Int {
        Int((Double(cadenceMin) * (1 + Double(spanPercent) / 100)).rounded())
    }

    /// Меняет нижнюю границу каденса и пересчитывает верхнюю по проценту.
    mutating func setCadenceMinDerivingMax(_ value: Int) {
        cadenceMin = value
        cadenceMax = RegulatorSettings.derivedCadenceMax(from: value, spanPercent: cadenceSpanPercent)
    }

    /// Меняет целевой пульс, сохраняя ширину зоны.
    mutating func setTargetHeartRateKeepingZoneWidth(_ value: Int) {
        let width = max(5, heartRateMax - heartRateMin)
        heartRateMax = value
        heartRateMin = max(40, value - width)
    }

    /// Возвращает копию с исправленными границами, если пользователь их перепутал.
    func normalized() -> RegulatorSettings {
        var copy = self
        if copy.cadenceMax <= copy.cadenceMin { copy.cadenceMax = copy.cadenceMin + 1 }
        if copy.heartRateMax <= copy.heartRateMin { copy.heartRateMax = copy.heartRateMin + 1 }
        copy.cadenceSpanPercent = min(50, max(1, copy.cadenceSpanPercent))
        copy.approachPercent = min(30, max(0, copy.approachPercent))
        copy.holdBand = max(0, copy.holdBand)
        copy.slowdownFactor = min(3, max(1, copy.slowdownFactor))
        copy.warmupMinutes = max(0, copy.warmupMinutes)
        copy.maxStep = max(1, copy.maxStep)
        copy.adjustInterval = max(1, copy.adjustInterval)
        copy.smoothingSeconds = max(0, copy.smoothingSeconds)
        copy.clickVolume = min(1, max(0, copy.clickVolume))
        return copy
    }
}
