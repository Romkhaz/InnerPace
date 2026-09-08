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

    private func row(_ second: Int, hr: Int, metronome: Int, warmup: Bool = false, overLimit: Bool = false) -> TelemetryRow {
        TelemetryRow(time: Date(timeIntervalSince1970: TimeInterval(second)), elapsed: TimeInterval(second), heartRate: hr,
                     smoothedHeartRate: Double(hr), decisionHeartRate: Double(hr), metronome: metronome, actualCadence: nil,
                     distanceMeters: 0, speedMetersPerSecond: nil, groundContactMs: nil, verticalOscillationCm: nil,
                     strideLengthMeters: nil, powerWatts: nil, efficiencyRecent: nil, warmup: warmup, overLimit: overLimit)
    }

    func testShortRunIsInsufficient() {
        let rows = (0..<600).map { row($0, hr: 150, metronome: 175) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .insufficient)
        XCTAssertFalse(a.hasSuggestion)
    }

    func testOnLimitSuggestsHigherTargetAndNotesWeakLever() {
        // Ритм на нижней границе весь забег, пульс 150–154 при цели 140: предел.
        var rows = (0..<120).map { row($0, hr: 120, metronome: 175, warmup: true) }
        rows += (120..<2000).map { row($0, hr: 150 + $0 % 5, metronome: 175, overLimit: true) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .onLimit)
        XCTAssertEqual(a.shareAtFloor, 1, accuracy: 0.001)
        XCTAssertEqual(a.suggestedTargetHeartRate, 155, "медиана 152 плюс 2, вверх до пяти")
        XCTAssertEqual(a.suggestedCadenceMin, 170, "рычаг неизвестен, ритм не менялся, но предложить снизить можно")
        XCTAssertNil(a.cadenceLever)

        let weak = ResponseEstimate(date: Date(), delaySeconds: 30, timeConstant: 30, gainPerStep: 0.1, fit: 0.3, noise: 2)
        let b = RunAnalyzer.assessEffort(rows: rows, settings: settings, response: weak)
        XCTAssertNil(b.suggestedCadenceMin, "ритм не рычаг: снижать его бессмысленно")
        XCTAssertEqual(b.cadenceLever ?? 0, 0.1, accuracy: 0.001)
    }

    func testOnLimitWithStrongLeverSuggestsLowerCadence() {
        var rows = (0..<2000).map { row($0, hr: 150, metronome: 175, overLimit: true) }
        rows += (2000..<2400).map { row($0, hr: 142, metronome: 185) }
        let strong = ResponseEstimate(date: Date(), delaySeconds: 30, timeConstant: 30, gainPerStep: 0.8, fit: 0.4, noise: 2)
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings, response: strong)
        XCTAssertEqual(a.verdict, .onLimit)
        XCTAssertEqual(a.suggestedCadenceMin, 170)
    }

    func testReserveSuggestsHigherCadenceMin() {
        // Ритм упёрся в верхнюю границу, пульс 125 ниже полосы удержания 132.
        let rows = (0..<2000).map { row($0, hr: 125, metronome: 190) }
        let a = RunAnalyzer.assessEffort(rows: rows, settings: settings)
        XCTAssertEqual(a.verdict, .reserve)
        XCTAssertEqual(a.suggestedCadenceMin, 180)
        XCTAssertNil(a.suggestedTargetHeartRate)
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
            ResponseEstimate(date: Date(), delaySeconds: lag - 14, timeConstant: 20, gainPerStep: 0.7, fit: 0.5, noise: noise)
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
