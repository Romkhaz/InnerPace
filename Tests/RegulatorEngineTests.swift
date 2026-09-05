import XCTest

final class RegulatorEngineTests: XCTestCase {
    private var settings: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMin = 130
        s.heartRateMax = 150
        s.approachPercent = 0
        s.holdBand = 3
        s.slowdownFactor = 1
        s.adjustInterval = 5
        s.smoothingSeconds = 0
        return s
    }

    func testAdjustsOnlyAfterInterval() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 180, "старт с нижней границы")
        engine.ingest(bpm: 130, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(4)))
        let adjustment = engine.tick(at: t0.addingTimeInterval(5))
        XCTAssertEqual(adjustment?.action, .speedUp(4))
        XCTAssertEqual(engine.cadence, 184)
    }

    func testFreezesWhenHeartRateIsStale() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        engine.ingest(bpm: 120, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(30)))
        XCTAssertEqual(engine.cadence, 180)
    }

    func testResumeDelaysNextAdjustment() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertNil(engine.tick(at: t0))
        engine.markPaused(at: t0.addingTimeInterval(30))
        engine.markResumed(at: t0.addingTimeInterval(60))
        engine.ingest(bpm: 120, at: t0.addingTimeInterval(61))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(62)))
        XCTAssertNotNil(engine.tick(at: t0.addingTimeInterval(65)))
    }

    func testSettingsChangePropagates() {
        var engine = RegulatorEngine(settings: settings)
        engine.reset()
        var narrower = settings
        narrower.cadenceMin = 195
        engine.settings = narrower
        XCTAssertEqual(engine.cadence, 195)
    }

    func testRegulationStartsOnceHeartRateReachesZoneFloor() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 180)
        XCTAssertFalse(engine.isRegulating)
        XCTAssertNil(engine.tick(at: t0))

        // Пульс ещё не дошёл до нижней границы зоны: ритм стоит на месте.
        engine.ingest(bpm: 110, at: t0.addingTimeInterval(5))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(5))?.action, .hold)
        engine.ingest(bpm: 125, at: t0.addingTimeInterval(10))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(10))?.action, .hold)
        XCTAssertEqual(engine.cadence, 180)
        XCTAssertFalse(engine.isRegulating)

        // Дошёл до 130: регулятор включается и с этого момента работает всегда.
        engine.ingest(bpm: 130, at: t0.addingTimeInterval(15))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(15))?.action, .speedUp(4))
        XCTAssertTrue(engine.isRegulating)
        engine.ingest(bpm: 110, at: t0.addingTimeInterval(20))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(20))?.action, .speedUp(4), "после включения пульс ниже границы уже не выключает регулятор")
    }

    func testResetDisarmsRegulation() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertNil(engine.tick(at: t0))
        engine.ingest(bpm: 140, at: t0.addingTimeInterval(5))
        XCTAssertNotNil(engine.tick(at: t0.addingTimeInterval(5)))
        XCTAssertTrue(engine.isRegulating)
        engine.reset(at: t0.addingTimeInterval(100))
        XCTAssertFalse(engine.isRegulating)
        XCTAssertEqual(engine.cadence, 180)
    }

    func testRawHeartRateAboveTargetBypassesSmoothing() {
        var s = settings
        s.smoothingSeconds = 30
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        engine.ingest(bpm: 135, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        for second in 1...5 { _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second))) }
        XCTAssertEqual(engine.cadence, 183)
        // Пульс прыгнул выше цели: сглаженный ещё около 136, решение принимается по сырому 160.
        engine.ingest(bpm: 160, at: t0.addingTimeInterval(6))
        XCTAssertLessThan(engine.smoothedHeartRate ?? 0, 140)
        XCTAssertEqual(engine.decisionHeartRate ?? 0, 160, accuracy: 0.001)
        let adjustment = engine.tick(at: t0.addingTimeInterval(10))
        XCTAssertEqual(adjustment?.action, .slowDown(2))
    }

    func testLogLine() {
        let up = RegulatorEngine.Adjustment(heartRate: 140.4, cadence: 186, action: .speedUp(2))
        XCTAssertEqual(up.logLine, "Пульс 140 → ритм 186 (+2)")
        let hold = RegulatorEngine.Adjustment(heartRate: 150, cadence: 186, action: .hold)
        XCTAssertNil(hold.logLine)
    }

    func testFormatting() {
        XCTAssertEqual(formatPace(312), "5:12")
        XCTAssertEqual(formatPace(nil), "—")
        XCTAssertEqual(formatPace(0), "—")
        XCTAssertTrue(formatDistance(3420).hasSuffix(" км"))
    }

    func testTelemetryCSV() {
        var recorder = TelemetryRecorder()
        recorder.start(settings: settings)
        recorder.append(TelemetryRow(time: Date(timeIntervalSince1970: 0), elapsed: 1, heartRate: 140,
                                     smoothedHeartRate: 139.5, decisionHeartRate: 139.5, metronome: 182,
                                     actualCadence: 178, distanceMeters: 3.2, speedMetersPerSecond: 3.1,
                                     groundContactMs: 240, verticalOscillationCm: 8.4, strideLengthMeters: 1.05,
                                     powerWatts: 250, efficiencyRecent: nil, warmup: true, decision: "a, b"))
        let csv = recorder.csv()
        XCTAssertTrue(csv.hasPrefix("# settings {"))
        XCTAssertTrue(csv.contains(TelemetryRecorder.header))
        XCTAssertTrue(csv.contains(",140,139.5,139.5,182,178,3.2,3.10,240,8.4,1.05,250,,1,a; b"))
    }
}
