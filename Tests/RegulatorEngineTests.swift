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
        s.warmupMinutes = 0
        return s
    }

    func testAdjustsOnlyAfterInterval() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 190, "разминки нет, но старт всё равно с середины диапазона")
        engine.ingest(bpm: 130, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(4)))
        let adjustment = engine.tick(at: t0.addingTimeInterval(5))
        XCTAssertEqual(adjustment?.action, .speedUp(4))
        XCTAssertEqual(engine.cadence, 194)
    }

    func testFreezesWhenHeartRateIsStale() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        engine.ingest(bpm: 120, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(30)))
        XCTAssertEqual(engine.cadence, 190)
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

    func testWarmupHoldsMidCadenceButAllowsSlowdown() {
        var s = settings
        s.warmupMinutes = 3
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 190)
        XCTAssertTrue(engine.isWarmingUp(at: t0.addingTimeInterval(60)))
        XCTAssertNil(engine.tick(at: t0), "первый такт только запускает отсчёт интервала")

        engine.ingest(bpm: 110, at: t0.addingTimeInterval(5))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(5))?.action, .hold)
        XCTAssertEqual(engine.cadence, 190)

        engine.ingest(bpm: 165, at: t0.addingTimeInterval(10))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(10))?.action, .slowDown(3))

        engine.ingest(bpm: 110, at: t0.addingTimeInterval(181))
        XCTAssertFalse(engine.isWarmingUp(at: t0.addingTimeInterval(181)))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(181))?.action, .speedUp(4))
    }

    func testPauseDoesNotConsumeWarmup() {
        var s = settings
        s.warmupMinutes = 3
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        engine.markPaused(at: t0.addingTimeInterval(60))
        XCTAssertEqual(engine.warmupRemaining(at: t0.addingTimeInterval(600)), 120, accuracy: 0.001)
        engine.markResumed(at: t0.addingTimeInterval(600))
        XCTAssertEqual(engine.warmupRemaining(at: t0.addingTimeInterval(600)), 120, accuracy: 0.001)
        XCTAssertFalse(engine.isWarmingUp(at: t0.addingTimeInterval(721)))
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
}
