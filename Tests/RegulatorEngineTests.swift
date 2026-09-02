import XCTest

final class RegulatorEngineTests: XCTestCase {
    private var settings: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMin = 130
        s.heartRateMax = 150
        s.adjustInterval = 5
        s.smoothingSeconds = 0
        return s
    }

    func testAdjustsOnlyAfterInterval() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset()
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
        engine.reset()
        engine.ingest(bpm: 120, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(30)))
        XCTAssertEqual(engine.cadence, 180)
    }

    func testResumeDelaysNextAdjustment() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset()
        XCTAssertNil(engine.tick(at: t0))
        engine.markResumed(at: t0.addingTimeInterval(60))
        engine.ingest(bpm: 120, at: t0.addingTimeInterval(61))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(62)))
        XCTAssertNotNil(engine.tick(at: t0.addingTimeInterval(65)))
    }

    func testSettingsChangePropagates() {
        var engine = RegulatorEngine(settings: settings)
        engine.reset()
        var narrower = settings
        narrower.cadenceMin = 190
        engine.settings = narrower
        XCTAssertEqual(engine.cadence, 190)
    }

    func testLogLine() {
        let up = RegulatorEngine.Adjustment(heartRate: 140.4, cadence: 186, action: .speedUp(2))
        XCTAssertEqual(up.logLine, "Пульс 140 → каденс 186 (+2)")
        let hold = RegulatorEngine.Adjustment(heartRate: 150, cadence: 186, action: .hold)
        XCTAssertNil(hold.logLine)
    }

    func testFormatting() {
        XCTAssertEqual(formatPace(312), "5:12")
        XCTAssertEqual(formatPace(nil), "—")
        XCTAssertEqual(formatPace(0), "—")
        XCTAssertTrue(formatDistance(3420).hasSuffix(" км"))
    }
}
