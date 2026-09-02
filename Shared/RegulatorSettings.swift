import Foundation

/// Параметры регулятора каденса по пульсу.
struct RegulatorSettings: Codable, Equatable {
    /// Нижняя граница каденса, шагов в минуту. С неё начинается тренировка.
    var cadenceMin: Int = 180
    /// Верхняя граница каденса, шагов в минуту.
    var cadenceMax: Int = 200
    /// Нижняя граница допустимой зоны пульса.
    var heartRateMin: Int = 130
    /// Верхняя граница зоны пульса. Регулятор ведёт пульс к этому значению.
    var heartRateMax: Int = 150
    /// Полоса под целевым пульсом, внутри которой каденс не меняется.
    var holdBand: Int = 3
    /// Сколько секунд между двумя подстройками каденса.
    var adjustInterval: TimeInterval = 5
    /// Максимальное изменение каденса за одну подстройку.
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
        cadenceMax = try c.decodeIfPresent(Int.self, forKey: .cadenceMax) ?? d.cadenceMax
        heartRateMin = try c.decodeIfPresent(Int.self, forKey: .heartRateMin) ?? d.heartRateMin
        heartRateMax = try c.decodeIfPresent(Int.self, forKey: .heartRateMax) ?? d.heartRateMax
        holdBand = try c.decodeIfPresent(Int.self, forKey: .holdBand) ?? d.holdBand
        adjustInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .adjustInterval) ?? d.adjustInterval
        maxStep = try c.decodeIfPresent(Int.self, forKey: .maxStep) ?? d.maxStep
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? d.smoothingSeconds
        halfTimeClick = try c.decodeIfPresent(Bool.self, forKey: .halfTimeClick) ?? d.halfTimeClick
        clickVolume = try c.decodeIfPresent(Double.self, forKey: .clickVolume) ?? d.clickVolume
    }

    var targetHeartRate: Int { heartRateMax }
    var isValid: Bool { cadenceMin < cadenceMax && heartRateMin < heartRateMax }

    /// Возвращает копию с исправленными границами, если пользователь их перепутал.
    func normalized() -> RegulatorSettings {
        var copy = self
        if copy.cadenceMax <= copy.cadenceMin { copy.cadenceMax = copy.cadenceMin + 1 }
        if copy.heartRateMax <= copy.heartRateMin { copy.heartRateMax = copy.heartRateMin + 1 }
        copy.holdBand = max(0, copy.holdBand)
        copy.maxStep = max(1, copy.maxStep)
        copy.adjustInterval = max(1, copy.adjustInterval)
        copy.smoothingSeconds = max(0, copy.smoothingSeconds)
        copy.clickVolume = min(1, max(0, copy.clickVolume))
        return copy
    }
}
