import XCTest

final class RunAnalysisTests: XCTestCase {
    private var settings: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 175
        s.cadenceMax = 190
        s.heartRateMin = 100
        s.heartRateMax = 140
        s.holdBand = 8
        return s
    }

    private func row(_ second: Int, hr: Int, metronome: Int, warmup: Bool = false, overLimit: Bool = false, probe: Bool = false,
                     actual: Int? = nil) -> TelemetryRow {
        TelemetryRow(time: Date(timeIntervalSince1970: TimeInterval(second)), elapsed: TimeInterval(second), heartRate: hr,
                     smoothedHeartRate: Double(hr), decisionHeartRate: Double(hr), metronome: metronome, actualCadence: actual,
                     distanceMeters: 0, speedMetersPerSecond: nil, groundContactMs: nil, verticalOscillationCm: nil,
                     strideLengthMeters: nil, powerWatts: nil, efficiencyRecent: nil, warmup: warmup, overLimit: overLimit, probe: probe)
    }

    /// Пробежка с ровным пульсом и одной пробой: ритм +8 на 90 с, отклик с задержкой 40 с
    /// и постоянной времени 20 с, 0,7 удара на шаг. Вне пробы ритм стоит, пульс шумит.
    private func probeRun() -> [TelemetryRow] {
        var rows: [TelemetryRow] = []
        var hr = 140.0
        var cadences: [Int] = []
        for s in 0..<2400 {
            let probe = (600..<690).contains(s)
            let cad = probe ? 188 : 180
            cadences.append(cad)
            let steady = 14 + 0.7 * Double(cadences[max(0, s - 40)])
            hr += (steady - hr) / 20
            let noise = Double((s * 7919) % 5) - 2   // детерминированный шум ±2
            rows.append(row(s, hr: Int((hr + noise).rounded()), metronome: cad, probe: probe))
        }
        return rows
    }

    func testProbeWindowGivesEstimateWhenWholeRunDoesNot() {
        let rows = probeRun()
        let estimate = RunAnalyzer.estimateResponse(rows: rows, settings: settings, date: Date())
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate?.fromProbe, true)
        XCTAssertEqual(estimate?.delaySeconds ?? 0, 40, accuracy: 10)
        XCTAssertEqual(estimate?.gainPerStep ?? 0, 0.7, accuracy: 0.2)
        XCTAssertGreaterThan(estimate?.fit ?? 0, 0.3)

        let withoutFlag = rows.map { r -> TelemetryRow in var c = r; c.probe = false; return c }
        let whole = RunAnalyzer.estimateResponse(rows: withoutFlag, settings: settings, date: Date())
        XCTAssertNotEqual(whole?.fromProbe, true)
        XCTAssertLessThan(whole?.fit ?? 0, estimate?.fit ?? 0, "по всей записи модель объясняет меньше, чем по окну пробы")
    }

    func testShortRunIsInsufficient() {
        let rows = (0..<600).map { row($0, hr: 150, metronome: 175) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .insufficient)
        XCTAssertFalse(a.hasSuggestion)
    }

    func testOnLimitSuggestsHigherTargetAndNotesWeakLever() {
        // Ритм на нижней границе весь забег, пульс 145–149 при цели 140: предел.
        var rows = (0..<120).map { row($0, hr: 120, metronome: 175, warmup: true) }
        rows += (120..<2000).map { row($0, hr: 145 + $0 % 5, metronome: 175, overLimit: true) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .onLimit)
        XCTAssertEqual(a.shareAtFloor, 1, accuracy: 0.001)
        XCTAssertEqual(a.suggestedTargetHeartRate, 150, "медиана 147 плюс 2, вверх до пяти")
        XCTAssertNil(a.suggestedCadenceMin, "сначала пульс: пока цель можно поднять, ритм не трогаем")
        XCTAssertNil(a.cadenceLever)

        let weak = ResponseEstimate(date: Date(), delaySeconds: 30, timeConstant: 30, gainPerStep: 0.1, fit: 0.3, noise: 2)
        let b = RunAnalyzer.assessEffort(rows: rows, settings: settings, response: weak)
        XCTAssertNil(b.suggestedCadenceMin, "ритм не рычаг: снижать его бессмысленно")
        XCTAssertEqual(b.cadenceLever ?? 0, 0.1, accuracy: 0.001)
    }

    func testOnLimitLowersCadenceOnlyWhenTargetCannotRiseAndAboveFloor() {
        // Пульс 165 при цели 140: цель поднять на 10 нельзя, тогда ритм на 5 вниз, но не ниже порога.
        var rows = (0..<2000).map { row($0, hr: 165, metronome: 175, overLimit: true) }
        rows += (2000..<2400).map { row($0, hr: 160, metronome: 185) }
        let strong = ResponseEstimate(date: Date(), delaySeconds: 30, timeConstant: 30, gainPerStep: 0.8, fit: 0.4, noise: 2)
        var s = settings
        s.cadenceFloor = 165
        let a = RunAnalyzer.assessEffort(rows: rows, settings: s, response: strong)
        XCTAssertEqual(a.verdict, .onLimit)
        XCTAssertNil(a.suggestedTargetHeartRate)
        XCTAssertEqual(a.suggestedCadenceMin, 170)
        s.cadenceFloor = 175
        let b = RunAnalyzer.assessEffort(rows: rows, settings: s, response: strong)
        XCTAssertNil(b.suggestedCadenceMin, "ниже порога 175 не предлагаем")
        var applied = s
        var withMin = a
        withMin.suggestedCadenceMin = 170
        withMin.apply(to: &applied)
        XCTAssertGreaterThanOrEqual(applied.cadenceMax, 187, "верхняя граница хотя бы плюс 10 %")
    }

    func testReserveSuggestsHigherCadenceMin() {
        // Ритм упёрся в верхнюю границу, пульс 125 ниже полосы удержания 132.
        let rows = (0..<2000).map { row($0, hr: 125, metronome: 190) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .reserve)
        XCTAssertEqual(a.suggestedCadenceMin, 180)
        XCTAssertNil(a.suggestedTargetHeartRate)
    }

    func testNoviceWhoCannotHoldTheBeat() {
        // Метроном 180, шаги 160, пульс 180: диагноз «ритм не по силам», цель не трогаем.
        var rows = (0..<60).map { row($0, hr: 120, metronome: 180, warmup: true, actual: 160) }
        rows += (60..<2400).map { row($0, hr: 180, metronome: 180, overLimit: true, actual: 158 + $0 % 4) }
        var s = settings
        s.cadenceFloor = 150
        let a = RunAnalyzer.assessEffort(rows: rows, settings: s)
        XCTAssertEqual(a.verdict, .cadenceTooHigh)
        XCTAssertEqual(a.suggestedCadenceMin, 160)
        var withFloor = settings
        withFloor.cadenceFloor = 170
        let floored = RunAnalyzer.assessEffort(rows: rows, settings: withFloor)
        XCTAssertEqual(floored.suggestedCadenceMin, 170, "не ниже порога 170")
        XCTAssertEqual(floored.cadenceMin, 175, "предложение помнит, с какими пределами бежали")
        XCTAssertNil(a.suggestedTargetHeartRate, "поднимать цель до 185 нельзя")
        a.apply(to: &s)
        XCTAssertEqual(s.cadenceMin, 160)
        XCTAssertEqual(s.cadenceMax, 190, "верхняя граница не опускается")
    }

    func testOnLimitDoesNotRaiseTargetByMoreThanTen() {
        let rows = (0..<2400).map { row($0, hr: 172, metronome: 175, overLimit: true, actual: 175) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .onLimit)
        XCTAssertNil(a.suggestedTargetHeartRate, "медиана 172 при цели 140: только бежать медленнее")
    }

    func testAthleteAtCeilingGetsHigherCeiling() {
        var s = settings
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMax = 160
        s.heartRateMin = 140
        let rows = (0..<2400).map { row($0, hr: 149, metronome: 200, actual: 200) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: s)
        XCTAssertEqual(a.verdict, .reserve)
        XCTAssertEqual(a.suggestedCadenceMin, 185)
        XCTAssertEqual(a.suggestedCadenceMax, 205)
        a.apply(to: &s)
        XCTAssertEqual(s.cadenceMin, 185)
        XCTAssertEqual(s.cadenceMax, 205, "потолок поднялся, а не обрезался до 190")
    }

    func testNeverArmedSuggestsLowerTarget() {
        var s = settings
        s.heartRateMax = 160
        s.heartRateMin = 140      // зона подхода со 144
        let rows = (0..<2400).map { row($0, hr: $0 < 120 ? 90 + $0 / 3 : 137, metronome: 180, warmup: true, actual: 180) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: s)
        XCTAssertEqual(a.verdict, .belowApproach)
        XCTAssertEqual(a.suggestedTargetHeartRate, 145, "медиана 137 плюс 5, вверх до пяти")
        XCTAssertEqual(a.regulatedSeconds, 0)
    }

    func testEconomyReport() {
        // 40 минут: скорость 2,8 м/с, пульс 140 в первой половине и 147 во второй при том же темпе.
        var rows: [TelemetryRow] = []
        for s in 0..<2400 {
            var r = row(s, hr: s < 1200 ? 140 : 147, metronome: 180, actual: 180)
            r.speedMetersPerSecond = 2.8
            r.distanceMeters = 2.8 * Double(s)
            r.phase = .run
            rows.append(r)
        }
        let e = RunAnalyzer.economy(rows: rows, restingHeartRate: 60)
        XCTAssertNotNil(e)
        // Средний пульс сверх покоя 83,5: 2,8 м/с × 60 / 83,5 ≈ 2,0 м/удар.
        XCTAssertEqual(e?.metersPerBeatAboveRest ?? 0, 2.0, accuracy: 0.05)
        XCTAssertEqual(e?.decouplingPercent ?? 0, 8.75, accuracy: 0.3, "80 к 87 ударам сверх покоя")
        XCTAssertGreaterThan(e?.driftBeatsPerHour ?? 0, 5)

        var short = rows
        short.removeLast(1300)
        XCTAssertNil(RunAnalyzer.economy(rows: short, restingHeartRate: 60), "меньше 20 минут не считаем")
        var warm = rows
        for i in warm.indices { warm[i].phase = .warmup }
        XCTAssertNil(RunAnalyzer.economy(rows: warm, restingHeartRate: 60), "разминка не в счёт")
    }

    func testKarvonenZones() {
        let z = HeartRateZones.karvonen(age: 40, restingHeartRate: 60)
        XCTAssertEqual(z.maxHeartRate, 180)
        XCTAssertEqual(z.zone2Low, 132)
        XCTAssertEqual(z.zone2High, 144)
        XCTAssertEqual(z.target, 145)
        XCTAssertEqual(z.lower, 128)
    }

    func testBalancedRun() {
        let rows = (0..<2000).map { row($0, hr: 134 + $0 % 5, metronome: 180 + ($0 / 60) % 6) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .balanced)
        XCTAssertFalse(a.hasSuggestion)
    }

    /// Пульс как инерционное звено с чистой задержкой 40 с: оценка должна найти задержку около 40–60
    /// и чувствительность около 0,7 удара на шаг.
    func testResponseEstimateRecoversLagAndGain() {
        var rows: [TelemetryRow] = []
        var hr = 130.0
        var cadences: [Int] = []
        for s in 0..<2400 {
            let cad = 175 + ((s / 240) % 2 == 0 ? 0 : 12)
            cadences.append(cad)
            let delayed = cadences[max(0, s - 40)]
            let steady = 15 + 0.7 * Double(delayed)
            hr += (steady - hr) / 20
            rows.append(row(s, hr: Int(hr.rounded()), metronome: cad))
        }
        let estimate = RunAnalyzer.estimateResponse(rows: rows, settings: settings, date: Date())
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate?.delaySeconds ?? 0, 40, accuracy: 10)
        XCTAssertEqual(estimate?.timeConstant ?? 0, 20, accuracy: 10)
        XCTAssertEqual(estimate?.gainPerStep ?? 0, 0.7, accuracy: 0.16)
        XCTAssertGreaterThan(estimate?.fit ?? 0, 0.8)
        XCTAssertEqual(estimate?.lagSeconds ?? 0, 54, accuracy: 12, "половина отклика: задержка плюс 0,69 постоянной времени")
    }

    func testResponseEstimateNeedsCadenceVariation() {
        let rows = (0..<2000).map { row($0, hr: 150, metronome: 175) }
        XCTAssertNil(RunAnalyzer.estimateResponse(rows: rows, settings: settings, date: Date()))
    }

    func testProfileNeedsThreeRunsAndSuggestsOnlyNotableChanges() {
        func estimate(lag: Double, noise: Double = 2) -> ResponseEstimate {
            ResponseEstimate(date: Date(), delaySeconds: lag - 14, timeConstant: 20, gainPerStep: 0.7, fit: 0.5, noise: noise, fromProbe: true)
        }
        XCTAssertNil(ProfileRecommendation.make(from: [estimate(lag: 40), estimate(lag: 45)], settings: settings))
        let close = ProfileRecommendation.make(from: [estimate(lag: 55), estimate(lag: 60), estimate(lag: 65)], settings: settings)
        XCTAssertEqual(close?.runsUsed, 3)
        XCTAssertNil(close?.predictSeconds, "медиана около 60 совпадает с настройкой")
        XCTAssertNil(close?.smoothingSeconds)
        let far = ProfileRecommendation.make(from: [estimate(lag: 40, noise: 4), estimate(lag: 35, noise: 4), estimate(lag: 45, noise: 4)], settings: settings)
        XCTAssertEqual(far?.predictSeconds, 40)
        XCTAssertEqual(far?.smoothingSeconds, 8, "шумный датчик, сглаживание дольше")
        let many = ProfileRecommendation.make(from: (0..<12).map { estimate(lag: Double(30 + $0)) }, settings: settings)
        XCTAssertEqual(many?.runsUsed, ProfileRecommendation.window)
    }

    func testSettingsStoreSnapshotAndRevert() {
        let defaults = UserDefaults(suiteName: "RunAnalysisTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        let original = store.settings
        XCTAssertNil(store.previousSettings)
        store.applyRecommendation { $0.setCadenceMinDerivingMax(185) }
        store.applyRecommendation { $0.predictSeconds = 45 }
        XCTAssertEqual(store.settings.cadenceMin, 185)
        XCTAssertEqual(store.settings.predictSeconds, 45)
        XCTAssertEqual(store.previousSettings, original, "снимок самый первый, до обоих применений")

        // Снимок переживает перезапуск.
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.previousSettings, original)
        reopened.revertToPrevious()
        XCTAssertEqual(reopened.settings, original)
        XCTAssertNil(reopened.previousSettings)
        XCTAssertNil(SettingsStore(defaults: defaults).previousSettings)
    }

    func testSummaryWithAnalysisRoundTrips() throws {
        var summary = WorkoutSummary(date: Date(), duration: 100, distanceMeters: 500, averageHeartRate: 140,
                                     averageCadence: nil, averageMetronome: nil, efficiencyMetersPerBeat: nil,
                                     averageGroundContactMs: nil, averageVerticalOscillationCm: nil, source: .watch)
        summary.assessment = RunAnalyzer.assessEffort(rows: [], settings: settings)
        let data = try XCTUnwrap(summary.encoded())
        XCTAssertEqual(WorkoutSummary.decode(data), summary)
        // Старый итог без полей анализа читается.
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000000","date":0,"duration":1,"distanceMeters":1,"source":"phone"}"#
        XCTAssertNotNil(WorkoutSummary.decode(Data(legacy.utf8)))
    }
}
