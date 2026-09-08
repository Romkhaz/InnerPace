import Foundation

/// Параметры регулятора каденса по пульсу.
struct RegulatorSettings: Codable, Equatable {
    /// Нижняя граница ритма, ударов в минуту. Основная настройка, с неё начинается забег.
    var cadenceMin: Int = 180
    /// Верхняя граница ритма. По умолчанию считается от нижней плюс `cadenceSpanPercent`,
    /// но не выше `cadenceMaxCap`; вручную можно поставить любую.
    var cadenceMax: Int = 190
    /// На сколько процентов верхняя граница ритма выше нижней, когда считается автоматически.
    var cadenceSpanPercent: Int = 15
    /// Нижняя граница зоны пульса. Задаёт масштаб шага регулятора и подсветку.
    var heartRateMin: Int = 130
    /// Целевой пульс. Основная настройка: регулятор ведёт пульс к этому значению.
    var heartRateMax: Int = 150
    /// За сколько процентов до цели рост ритма замедляется до одного шага за интервал.
    var approachPercent: Int = 10
    /// Полоса под целевым пульсом, внутри которой ритм не растёт.
    var holdBand: Int = 8
    /// Во сколько раз ритм падает быстрее, чем растёт. От 1 до 10.
    var slowdownFactor: Double = 3
    /// Сколько секунд между двумя подстройками ритма.
    var adjustInterval: TimeInterval = 5
    /// Базовый максимальный шаг подстройки. Спуск считается от него напрямую,
    /// подъём умножается на `ascentFactor`.
    var maxStep: Int = 4
    /// Во сколько раз подъём медленнее базового шага. 0,5 значит вдвое медленнее.
    var ascentFactor: Double = 0.5
    /// Сколько секунд пульс должен продержаться в зоне подхода, чтобы регулятор включился.
    var armSeconds: Int = 30
    /// Горизонт прогноза пульса, секунды. Решение принимается по пульсу, который
    /// ожидается через это время при текущем тренде, а не по текущему. Ноль отключает прогноз.
    var predictSeconds: Int = 60
    /// Проба отклика: раз за пробежку ритм на `probeSeconds` поднимается на `probeStep`,
    /// чтобы измерить задержку и чувствительность пульса. Отключается сама, когда профиль набран.
    var responseProbe: Bool = true
    /// Разминка, секунды: ритм стоит на нижней границе, регулятор не включается,
    /// а предел считается от цели минус `warmupMargin`. Ноль отключает.
    var warmupSeconds: Int = 480
    /// Возраст и пульс покоя для зон по Карвонену. Если Здоровье даёт свои значения, они главнее.
    var age: Int = 40
    var restingHeartRate: Int = 60
    /// Версия схемы настроек. Старые записи без версии приводятся к новым значениям по умолчанию,
    /// где старое значение по умолчанию оказалось неудачным.
    var schemaVersion: Int = RegulatorSettings.currentSchemaVersion
    /// Постоянная времени сглаживания пульса, секунды.
    var smoothingSeconds: Double = 5
    /// Щёлкать на каждый второй шаг.
    var halfTimeClick: Bool = false
    /// Громкость щелчка, от 0 до 1.
    var clickVolume: Double = 0.8
    /// Режим разработчика: посекундная телеметрия пишется в файл.
    /// В тестовых сборках включён принудительно, см. `telemetryForcedOn`.
    var developerMode: Bool = true

    /// Пока идёт тестирование, телеметрия включена всегда. Перед публикацией в App Store
    /// поставить false: тогда заработает переключатель в настройках.
    static let telemetryForcedOn = true
    /// Потолок автоматически вычисляемой верхней границы ритма.
    static let cadenceMaxCap = 190
    static let currentSchemaVersion = 3
    /// Повтор «сбавь» в настройках до версии 3: ноль, то есть только на переходах.
    /// На долгом пределе один «сбавь» терялся.
    static let legacyVoiceRepeat = 0
    /// Цель ниже этого почти наверняка ошибка: регулятор будет всё время в пределе.
    static let lowTargetWarning = 100
    /// Цель выше этого почти наверняка ошибка: регулятор, скорее всего, не включится.
    static let highTargetWarning = 190
    /// На сколько ниже цели должен оставаться пульс на разминке.
    static let warmupMargin = 10
    /// Заминка: ритм снижается на единицу раз в столько секунд до нижней границы минус `cooldownDrop`.
    static let cooldownStepSeconds: TimeInterval = 10
    static let cooldownDrop = 15
    static let probeStep = 8
    static let probeSeconds: TimeInterval = 90
    /// Сколько секунд пульс должен ровно держаться в полосе удержания перед пробой.
    static let probeReadySeconds: TimeInterval = 60
    /// Полоса удержания в настройках до версии 2. Оказалась слишком узкой: ритм рос,
    /// пока пульс не подходил к цели вплотную, и инерция выносила его выше.
    static let legacyHoldBand = 3
    /// Оформление: авто, светлая или тёмная.
    var theme: AppTheme = .auto
    /// Голосовые подсказки «сбавь» и «в норме».
    var voiceCues: Bool = true
    /// Повтор «сбавь», секунды. Ноль означает только на переходах.
    var voiceRepeatSeconds: Int = 60
    /// Громкость голоса, от 0 до 1.
    var voiceVolume: Double = 1

    static let `default` = RegulatorSettings()

    init() {}

    /// Ключи могут отсутствовать в старых сохранённых настройках, поэтому каждый читаем с запасным значением.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RegulatorSettings()
        cadenceMin = try c.decodeIfPresent(Int.self, forKey: .cadenceMin) ?? d.cadenceMin
        cadenceSpanPercent = try c.decodeIfPresent(Int.self, forKey: .cadenceSpanPercent) ?? d.cadenceSpanPercent
        let storedMax = try c.decodeIfPresent(Int.self, forKey: .cadenceMax)
        let uncapped = Int((Double(cadenceMin) * (1 + Double(cadenceSpanPercent) / 100)).rounded())
        // Старые сохранённые настройки с автоматическим потолком выше 190 приводим к новому правилу;
        // значение, выставленное вручную, не трогаем.
        if let storedMax, storedMax != uncapped {
            cadenceMax = storedMax
        } else {
            cadenceMax = RegulatorSettings.derivedCadenceMax(from: cadenceMin, spanPercent: cadenceSpanPercent)
        }
        heartRateMin = try c.decodeIfPresent(Int.self, forKey: .heartRateMin) ?? d.heartRateMin
        heartRateMax = try c.decodeIfPresent(Int.self, forKey: .heartRateMax) ?? d.heartRateMax
        approachPercent = try c.decodeIfPresent(Int.self, forKey: .approachPercent) ?? d.approachPercent
        let storedVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let storedHoldBand = try c.decodeIfPresent(Int.self, forKey: .holdBand) ?? d.holdBand
        holdBand = storedVersion < 2 && storedHoldBand == RegulatorSettings.legacyHoldBand ? d.holdBand : storedHoldBand
        schemaVersion = RegulatorSettings.currentSchemaVersion
        slowdownFactor = try c.decodeIfPresent(Double.self, forKey: .slowdownFactor) ?? d.slowdownFactor
        adjustInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .adjustInterval) ?? d.adjustInterval
        maxStep = try c.decodeIfPresent(Int.self, forKey: .maxStep) ?? d.maxStep
        ascentFactor = try c.decodeIfPresent(Double.self, forKey: .ascentFactor) ?? d.ascentFactor
        armSeconds = try c.decodeIfPresent(Int.self, forKey: .armSeconds) ?? d.armSeconds
        predictSeconds = try c.decodeIfPresent(Int.self, forKey: .predictSeconds) ?? d.predictSeconds
        responseProbe = try c.decodeIfPresent(Bool.self, forKey: .responseProbe) ?? d.responseProbe
        warmupSeconds = try c.decodeIfPresent(Int.self, forKey: .warmupSeconds) ?? d.warmupSeconds
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? d.age
        restingHeartRate = try c.decodeIfPresent(Int.self, forKey: .restingHeartRate) ?? d.restingHeartRate
        smoothingSeconds = try c.decodeIfPresent(Double.self, forKey: .smoothingSeconds) ?? d.smoothingSeconds
        halfTimeClick = try c.decodeIfPresent(Bool.self, forKey: .halfTimeClick) ?? d.halfTimeClick
        clickVolume = try c.decodeIfPresent(Double.self, forKey: .clickVolume) ?? d.clickVolume
        developerMode = RegulatorSettings.telemetryForcedOn
            ? true
            : (try c.decodeIfPresent(Bool.self, forKey: .developerMode) ?? d.developerMode)
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? d.theme
        voiceCues = try c.decodeIfPresent(Bool.self, forKey: .voiceCues) ?? d.voiceCues
        let storedRepeat = try c.decodeIfPresent(Int.self, forKey: .voiceRepeatSeconds) ?? d.voiceRepeatSeconds
        voiceRepeatSeconds = storedVersion < 3 && storedRepeat == RegulatorSettings.legacyVoiceRepeat ? d.voiceRepeatSeconds : storedRepeat
        voiceVolume = try c.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? d.voiceVolume
    }

    var targetHeartRate: Int { heartRateMax }
    var isTargetSuspiciouslyLow: Bool { heartRateMax < RegulatorSettings.lowTargetWarning }
    var isTargetSuspiciouslyHigh: Bool { heartRateMax > RegulatorSettings.highTargetWarning }
    var isValid: Bool { cadenceMin < cadenceMax && heartRateMin < heartRateMax }

    /// Пульс, с которого рост ритма замедляется.
    var approachHeartRate: Double {
        Double(heartRateMax) * (1 - Double(approachPercent) / 100)
    }

    /// Пульс, с которого ритм больше не растёт.
    var holdHeartRate: Double {
        Double(heartRateMax - holdBand)
    }

    static func derivedCadenceMax(from cadenceMin: Int, spanPercent: Int) -> Int {
        let uncapped = Int((Double(cadenceMin) * (1 + Double(spanPercent) / 100)).rounded())
        return max(cadenceMin + 1, min(uncapped, cadenceMaxCap))
    }

    /// Меняет нижнюю границу ритма и пересчитывает верхнюю по проценту.
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
        copy.slowdownFactor = min(10, max(1, copy.slowdownFactor))
        copy.maxStep = max(1, copy.maxStep)
        copy.ascentFactor = min(1, max(0.1, copy.ascentFactor))
        copy.armSeconds = min(300, max(0, copy.armSeconds))
        copy.predictSeconds = min(120, max(0, copy.predictSeconds))
        copy.warmupSeconds = min(1800, max(0, copy.warmupSeconds))
        copy.age = min(100, max(10, copy.age))
        copy.restingHeartRate = min(120, max(30, copy.restingHeartRate))
        copy.adjustInterval = max(1, copy.adjustInterval)
        copy.smoothingSeconds = max(0, copy.smoothingSeconds)
        copy.clickVolume = min(1, max(0, copy.clickVolume))
        copy.voiceRepeatSeconds = min(120, max(0, copy.voiceRepeatSeconds))
        copy.voiceVolume = min(1, max(0, copy.voiceVolume))
        return copy
    }
}
