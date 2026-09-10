import Foundation

/// Оценка усилия по одной пробежке: хватало ли регулятору диапазона ритма,
/// чтобы держать пульс у цели, и что предложить на следующий раз.
struct EffortAssessment: Codable, Equatable {
    enum Verdict: String, Codable {
        /// Регулятор работал меньше `minimumSeconds`, выводов нет.
        case insufficient
        /// Ритм упирался в нижнюю границу, пульс выше цели: бежать медленнее или поднять цель.
        case onLimit
        /// Ритм у верхней границы, пульс ниже полосы удержания: есть запас.
        case reserve
        /// Пределы подобраны нормально.
        case balanced
        /// Пульс за всю пробежку не дошёл до зоны подхода: цель слишком высока для этого темпа.
        case belowApproach
        /// Фактический каденс заметно ниже метронома: ритм не по силам.
        case cadenceTooHigh
    }

    var verdict: Verdict
    /// Пределы, при которых бежали: предложение показывается относительно них,
    /// а не текущих настроек устройства, где смотрят отчёт.
    var cadenceMin: Int = 0
    var cadenceMax: Int = 0
    var targetHeartRate: Int = 0
    var regulatedSeconds: Int
    var shareAtFloor: Double
    var shareAtCeiling: Double
    var shareAboveTarget: Double
    var shareInBand: Double
    var overLimitSeconds: Int
    /// Медиана пульса, пока ритм стоял на нижней границе.
    var heartRateAtFloor: Double?
    /// Медиана пульса, пока ритм стоял на верхней границе.
    var heartRateAtCeiling: Double?
    /// Сколько ударов пульса даёт один шаг ритма, из модели отклика. Меньше 0,3 значит ритм не рычаг.
    var cadenceLever: Double?
    /// Медиана фактического каденса с шагомера.
    var actualCadence: Double?
    var suggestedCadenceMin: Int?
    var suggestedCadenceMax: Int?
    var suggestedTargetHeartRate: Int?

    /// Сколько секунд регулятор должен проработать, чтобы оценка что-то значила.
    static let minimumSeconds = 1200
    /// Слабее этого ритм на пульс почти не влияет.
    static let weakLever = 0.3
    /// Фактический каденс ниже метронома на столько и больше значит ритм не по силам.
    static let cadenceShortfall = 8.0
    /// Выше этого цель за один раз не поднимаем: дальше совет только бежать медленнее.
    static let maxTargetRaise = 10
    static let cadenceMaxLimit = 220

    var hasSuggestion: Bool { suggestedCadenceMin != nil || suggestedCadenceMax != nil || suggestedTargetHeartRate != nil }

    /// Применяет предложение к настройкам. Верхняя граница ритма не опускается:
    /// если она была выставлена выше автоматической, так и остаётся.
    func apply(to settings: inout RegulatorSettings) {
        if let c = suggestedCadenceMin {
            settings.cadenceMin = c
            settings.cadenceMax = max(settings.cadenceMax, RegulatorSettings.derivedCadenceMax(from: c, spanPercent: settings.cadenceSpanPercent))
        }
        if let m = suggestedCadenceMax { settings.cadenceMax = max(m, settings.cadenceMin + 1) }
        if let t = suggestedTargetHeartRate { settings.setTargetHeartRateKeepingZoneWidth(t) }
    }
}

/// Оценка отклика пульса на ритм по одной пробежке. Пульс моделируется как инерционное
/// звено с чистой задержкой: через `delaySeconds` после смены ритма пульс начинает
/// стремиться к новому уровню с постоянной времени `timeConstant`, по `gainPerStep`
/// ударов на шаг ритма. Параметры подбираются перебором по всей записи.
struct ResponseEstimate: Codable, Equatable {
    var date: Date
    /// Чистая задержка, секунды.
    var delaySeconds: Double
    /// Постоянная времени, секунды.
    var timeConstant: Double
    /// Ударов пульса на шаг ритма.
    var gainPerStep: Double
    /// Доля разброса пульса, которую объясняет модель, от 0 до 1.
    var fit: Double
    /// Разброс сырого пульса вокруг сглаженного.
    var noise: Double
    /// Оценка получена по пробе отклика, а не по всей записи.
    var fromProbe: Bool = false

    /// Время до половины отклика: то, на сколько вперёд имеет смысл прогноз.
    var lagSeconds: Double { delaySeconds + timeConstant * 0.69 }

    static let minimumSeconds = 900
    static let minimumCadenceSpread = 1.5
    /// Порог качества модели. По всей записи связь ритма с пульсом слабая, и модель
    /// с качеством 0,1 давала задержку 130 с и чувствительность 1,25: мусор в профиле.
    static let minimumFit = 0.3
    static let minimumProbeFit = 0.3
}

enum RunAnalyzer {
    static func assessEffort(rows: [TelemetryRow], settings: RegulatorSettings, response: ResponseEstimate? = nil) -> EffortAssessment {
        let reg = rows.filter { !$0.warmup && $0.heartRate != nil }
        let n = reg.count
        let target = Double(settings.targetHeartRate)
        let hold = settings.holdHeartRate
        func share(_ predicate: (TelemetryRow) -> Bool) -> Double {
            n == 0 ? 0 : Double(reg.filter(predicate).count) / Double(n)
        }
        let atFloor = share { $0.metronome <= settings.cadenceMin }
        let atCeiling = share { $0.metronome >= settings.cadenceMax }
        let above = share { Double($0.heartRate ?? 0) > target }
        let inBand = share { let h = Double($0.heartRate ?? 0); return h >= hold && h <= target }
        let overLimit = reg.filter(\.overLimit).count
        let floorHR = median(reg.filter { $0.metronome <= settings.cadenceMin }.compactMap { $0.heartRate.map(Double.init) }, minimum: 120)
        let ceilingHR = median(reg.filter { $0.metronome >= settings.cadenceMax }.compactMap { $0.heartRate.map(Double.init) }, minimum: 120)
        // Рычаг ритма берём из модели отклика: прямое сравнение пульса на разном ритме
        // в замкнутом контуре обманывает, регулятор сам поднимает ритм при низком пульсе.
        let lever = response?.gainPerStep
        let actualSamples = reg.compactMap { $0.actualCadence.map(Double.init) }
        let actual = actualSamples.count >= max(60, n * 6 / 10) ? median(actualSamples) : nil

        var assessment = EffortAssessment(
            verdict: .insufficient, cadenceMin: settings.cadenceMin, cadenceMax: settings.cadenceMax,
            targetHeartRate: settings.targetHeartRate, regulatedSeconds: n, shareAtFloor: atFloor, shareAtCeiling: atCeiling,
            shareAboveTarget: above, shareInBand: inBand, overLimitSeconds: overLimit,
            heartRateAtFloor: floorHR, heartRateAtCeiling: ceilingHR, cadenceLever: lever, actualCadence: actual
        )
        guard n >= EffortAssessment.minimumSeconds else {
            // Регулятор так и не включился, а бежали долго: пульс не дошёл до зоны подхода.
            let withHR = rows.filter { $0.heartRate != nil }
            if withHR.count >= EffortAssessment.minimumSeconds,
               let recent = median(withHR.suffix(600).compactMap { $0.smoothedHeartRate ?? $0.heartRate.map(Double.init) }),
               recent < settings.approachHeartRate {
                assessment.verdict = .belowApproach
                let proposed = Int(((recent + 5) / 5).rounded(.up)) * 5
                if proposed < settings.targetHeartRate { assessment.suggestedTargetHeartRate = proposed }
            }
            return assessment
        }

        if let actual, let metro = median(reg.map { Double($0.metronome) }),
           actual <= metro - EffortAssessment.cadenceShortfall {
            assessment.verdict = .cadenceTooHigh
            let proposed = max(settings.cadenceFloor, Int((actual / 5).rounded()) * 5)
            if proposed < settings.cadenceMin { assessment.suggestedCadenceMin = proposed }
        } else if atFloor >= 0.4, above >= 0.3 || Double(overLimit) >= 0.2 * Double(n) {
            assessment.verdict = .onLimit
            // Сначала пульс: поднять цель. Ритм снижаем только если цель поднять уже нельзя,
            // и никогда ниже `cadenceFloor`: низкий каденс травмоопасен.
            if let floorHR {
                let proposed = Int(((floorHR + 2) / 5).rounded(.up)) * 5
                if proposed > settings.targetHeartRate, proposed <= settings.targetHeartRate + EffortAssessment.maxTargetRaise {
                    assessment.suggestedTargetHeartRate = proposed
                }
            }
            if assessment.suggestedTargetHeartRate == nil, (lever ?? 1) >= EffortAssessment.weakLever,
               settings.cadenceMin - 5 >= settings.cadenceFloor {
                assessment.suggestedCadenceMin = settings.cadenceMin - 5
            }
        } else if above <= 0.1, (atCeiling >= 0.3 && (ceilingHR ?? target) < hold) || share({ Double($0.heartRate ?? 0) < hold }) >= 0.6 {
            assessment.verdict = .reserve
            if settings.cadenceMin + 5 < settings.cadenceMax {
                assessment.suggestedCadenceMin = settings.cadenceMin + 5
            }
            // Упёрлись в потолок ритма, а пульс всё ещё ниже полосы: потолок тоже можно поднять.
            if atCeiling >= 0.3, settings.cadenceMax + 5 <= EffortAssessment.cadenceMaxLimit {
                assessment.suggestedCadenceMax = settings.cadenceMax + 5
            }
        } else {
            assessment.verdict = .balanced
        }
        return assessment
    }

    /// Оценка отклика. Если в записи была проба, модель подбирается по её окну:
    /// 20 с до, сама проба и 60 с после, там ступенька ритма чистая. Иначе по всей
    /// записи после включения, где вариации ритма может и не хватить.
    static func estimateResponse(rows: [TelemetryRow], settings: RegulatorSettings, date: Date) -> ResponseEstimate? {
        let noise = standardDeviation(rows.compactMap { r -> Double? in
            guard let hr = r.heartRate, let s = r.smoothedHeartRate else { return nil }
            return Double(hr) - s
        })
        if let first = rows.firstIndex(where: \.probe), let last = rows.lastIndex(where: \.probe) {
            let window = Array(rows[max(0, first - 20)...min(rows.count - 1, last + 60)]).filter { $0.heartRate != nil }
            if window.count >= 60, let fit = fitModel(cad: window.map { Double($0.metronome) },
                                                      hr: window.map { Double($0.heartRate ?? 0) }),
               fit.fit >= ResponseEstimate.minimumProbeFit {
                return ResponseEstimate(date: date, delaySeconds: fit.delay, timeConstant: fit.tau,
                                        gainPerStep: fit.gain, fit: fit.fit, noise: noise, fromProbe: true)
            }
        }
        let reg = rows.filter { !$0.warmup && $0.heartRate != nil }
        guard reg.count >= ResponseEstimate.minimumSeconds else { return nil }
        let cad = reg.map { Double($0.metronome) }
        guard standardDeviation(cad) >= ResponseEstimate.minimumCadenceSpread,
              let fit = fitModel(cad: cad, hr: reg.map { Double($0.heartRate ?? 0) }),
              fit.fit >= ResponseEstimate.minimumFit else { return nil }
        return ResponseEstimate(date: date, delaySeconds: fit.delay, timeConstant: fit.tau,
                                gainPerStep: fit.gain, fit: fit.fit, noise: noise, fromProbe: false)
    }

    /// Перебор модели: инерционное звено с задержкой на отклонении ритма от среднего,
    /// уровень подбирается по среднему остатку. На часах занимает доли секунды.
    static func fitModel(cad: [Double], hr: [Double]) -> (delay: Double, tau: Double, gain: Double, fit: Double)? {
        let n = min(cad.count, hr.count)
        guard n > 30 else { return nil }
        let variance = standardDeviation(Array(hr[0..<n])) * standardDeviation(Array(hr[0..<n]))
        guard variance > 0 else { return nil }
        let meanCad = mean(Array(cad[0..<n]))
        var best: (error: Double, delay: Int, tau: Double, gain: Double)? = nil
        for delay in stride(from: 10, through: 90, by: 10) {
            for tau in [10.0, 20, 30, 45, 60, 90] {
                for gain in stride(from: 0.2, through: 1.4, by: 0.15) {
                    var h = gain * (cad[0] - meanCad)
                    var response = [Double](repeating: 0, count: n)
                    for t in 0..<n {
                        let input = gain * (cad[max(0, t - delay)] - meanCad)
                        h += (input - h) / tau
                        response[t] = h
                    }
                    var offset = 0.0
                    for t in 0..<n { offset += hr[t] - response[t] }
                    offset /= Double(n)
                    var error = 0.0
                    for t in 0..<n {
                        let e = hr[t] - response[t] - offset
                        error += e * e
                    }
                    error /= Double(n)
                    if best == nil || error < best!.error { best = (error, delay, tau, gain) }
                }
            }
        }
        guard let best else { return nil }
        return (Double(best.delay), best.tau, best.gain, 1 - best.error / variance)
    }

    // MARK: - Статистика

    static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    static func median(_ xs: [Double], minimum: Int = 1) -> Double? {
        guard xs.count >= max(1, minimum) else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func standardDeviation(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)).squareRoot()
    }

    static func correlation(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = min(xs.count, ys.count)
        guard n > 1 else { return 0 }
        let mx = mean(Array(xs[0..<n])), my = mean(Array(ys[0..<n]))
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<n {
            num += (xs[i] - mx) * (ys[i] - my)
            dx += (xs[i] - mx) * (xs[i] - mx)
            dy += (ys[i] - my) * (ys[i] - my)
        }
        guard dx > 0, dy > 0 else { return 0 }
        return num / (dx * dy).squareRoot()
    }

    static func slope(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = min(xs.count, ys.count)
        guard n > 1 else { return 0 }
        let mx = mean(Array(xs[0..<n])), my = mean(Array(ys[0..<n]))
        var num = 0.0, den = 0.0
        for i in 0..<n {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        return den > 0 ? num / den : 0
    }
}

/// Профиль бегуна: медиана оценок отклика по последним пробежкам и что из неё
/// следует для параметров расчёта. Предлагает только заметные изменения.
struct ProfileRecommendation: Equatable {
    var runsUsed: Int
    var lagSeconds: Double
    var gainPerStep: Double
    var noise: Double
    /// nil значит менять не нужно.
    var predictSeconds: Int?
    var smoothingSeconds: Double?

    static let minimumRuns = 3
    static let window = 8

    var hasSuggestion: Bool { predictSeconds != nil || smoothingSeconds != nil }

    /// Оценки должны быть отсортированы от новых к старым.
    static func make(from estimates: [ResponseEstimate], settings: RegulatorSettings) -> ProfileRecommendation? {
        let recent = Array(estimates.prefix(window))
        guard recent.count >= minimumRuns,
              let lag = RunAnalyzer.median(recent.map(\.lagSeconds)),
              let gain = RunAnalyzer.median(recent.map(\.gainPerStep)),
              let noise = RunAnalyzer.median(recent.map(\.noise)) else { return nil }
        var rec = ProfileRecommendation(runsUsed: recent.count, lagSeconds: lag, gainPerStep: gain, noise: noise)
        let predict = min(120, max(20, Int((lag / 5).rounded()) * 5))
        if abs(predict - settings.predictSeconds) >= 10 { rec.predictSeconds = predict }
        let smoothing: Double = noise >= 3 ? 8 : (noise <= 1.5 ? 3 : 5)
        if abs(smoothing - settings.smoothingSeconds) >= 2 { rec.smoothingSeconds = smoothing }
        return rec
    }
}
