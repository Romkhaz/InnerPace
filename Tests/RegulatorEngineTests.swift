import XCTest

final class RegulatorEngineTests: XCTestCase {
    private var settings: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMin = 130
        s.heartRateMax = 150
        s.approachPercent = 10   // зона подхода и включение регулятора с 135
        s.holdBand = 3           // удержание со 147
        s.slowdownFactor = 1
        s.adjustInterval = 5
        s.smoothingSeconds = 0
        s.ascentFactor = 1
        s.armSeconds = 0
        s.predictSeconds = 0
        return s
    }

    /// Секунда за секундой подаёт пульс и тикает движок; возвращает последнее решение.
    @discardableResult
    private func feed(_ engine: inout RegulatorEngine, from: Int, through: Int, bpm: (Int) -> Int,
                      t0: Date) -> RegulatorEngine.Adjustment? {
        var last: RegulatorEngine.Adjustment?
        for second in from...through {
            let t = t0.addingTimeInterval(TimeInterval(second))
            engine.ingest(bpm: bpm(second), at: t)
            if let a = engine.tick(at: t) { last = a }
        }
        return last
    }

    func testTrendPredictsHeartRate() {
        var s = settings
        s.predictSeconds = 60
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        // Пульс растёт на 6 ударов в минуту: 120 → 122 за 20 секунд.
        feed(&engine, from: 0, through: 20, bpm: { 120 + $0 / 10 }, t0: t0)
        XCTAssertEqual(engine.trendPerMinute, 6, accuracy: 1.5)
        XCTAssertEqual(engine.predictedHeartRate ?? 0, 128, accuracy: 2, "через минуту ожидаем около 128")
    }

    func testRisingHeartRateStopsAscentEarly() {
        var s = settings
        s.holdBand = 8            // удержание со 142
        s.predictSeconds = 60
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        // Пульс 136 и растёт на 12 ударов в минуту: прогноз 148 выше цели, ритм не растёт.
        feed(&engine, from: 0, through: 30, bpm: { 130 + $0 / 5 }, t0: t0)
        XCTAssertGreaterThan(engine.trendPerMinute, 9)
        XCTAssertGreaterThan(engine.predictedHeartRate ?? 0, 147)
        let adjustment = engine.tick(at: t0.addingTimeInterval(35))
        XCTAssertNotEqual(adjustment?.action, .speedUp(1))

        // Тот же пульс без тренда: ритм растёт по одному.
        var flat = RegulatorEngine(settings: s)
        flat.reset(at: t0)
        feed(&flat, from: 0, through: 30, bpm: { _ in 136 }, t0: t0)
        XCTAssertEqual(flat.trendPerMinute, 0, accuracy: 0.01)
        XCTAssertEqual(flat.tick(at: t0.addingTimeInterval(35))?.action, .speedUp(1))
    }

    func testFallingHeartRateSoftensDescent() {
        var s = settings
        s.predictSeconds = 60
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        // Зона подхода: регулятор включён, ритм подрос.
        feed(&engine, from: 0, through: 30, bpm: { _ in 136 }, t0: t0)
        XCTAssertGreaterThan(engine.cadence, 180)
        let before = engine.cadence
        // Пульс скакнул до 160 и падает на 12 ударов в минуту до 153: сырой всё ещё выше цели 150,
        // поэтому решение по сырому, а не по прогнозу, и спуск идёт по фактическому превышению.
        feed(&engine, from: 31, through: 70, bpm: { 160 - ($0 - 31) / 5 }, t0: t0)
        XCTAssertLessThan(engine.trendPerMinute, -9)
        XCTAssertLessThan(engine.predictedHeartRate ?? 0, 145)
        XCTAssertEqual(engine.decisionHeartRate ?? 0, 153, accuracy: 0.001, "сырой пульс выше цели побеждает прогноз")
        XCTAssertLessThan(engine.cadence, before)
    }

    func testOverLimitNotDeclaredWhileHeartRateFalls() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertNil(engine.tick(at: t0))
        // Ритм на нижней границе, пульс выше цели, но падает на 12 ударов в минуту.
        feed(&engine, from: 1, through: 25, bpm: { 165 - $0 / 5 }, t0: t0)
        XCTAssertEqual(engine.cadence, 180)
        XCTAssertLessThan(engine.trendPerMinute, -9)
        XCTAssertFalse(engine.isOverLimit, "пульс сам идёт вниз, «сбавь» не нужно")
        // Пульс перестал падать: как только тренд выровнялся, через десять секунд предел.
        feed(&engine, from: 26, through: 40, bpm: { _ in 160 }, t0: t0)
        XCTAssertFalse(engine.isOverLimit, "окно тренда ещё помнит спад")
        feed(&engine, from: 41, through: 60, bpm: { _ in 160 }, t0: t0)
        XCTAssertTrue(engine.isOverLimit)
    }

    func testAdjustsOnlyAfterInterval() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 180, "старт с нижней границы")
        engine.ingest(bpm: 136, at: t0)
        XCTAssertNil(engine.tick(at: t0))
        XCTAssertNil(engine.tick(at: t0.addingTimeInterval(4)))
        let adjustment = engine.tick(at: t0.addingTimeInterval(5))
        XCTAssertEqual(adjustment?.action, .speedUp(1), "в зоне подхода по одному удару")
        XCTAssertEqual(engine.cadence, 181)
    }

    func testFreezesWhenHeartRateIsStale() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        engine.ingest(bpm: 136, at: t0)
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
        engine.ingest(bpm: 136, at: t0.addingTimeInterval(61))
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

    func testRegulationArmsAfterHoldingInApproachZone() {
        var s = settings
        s.armSeconds = 30
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertEqual(engine.cadence, 180)
        XCTAssertNil(engine.tick(at: t0))

        // Ниже зоны подхода: ждём, сколько бы ни прошло времени.
        for second in 1...60 {
            engine.ingest(bpm: 128, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertFalse(engine.isRegulating)
        XCTAssertEqual(engine.cadence, 180)

        // Вошёл в зону подхода: включение только после 30 секунд подряд.
        for second in 61...89 {
            engine.ingest(bpm: 136, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertFalse(engine.isRegulating, "29 секунд ещё мало")
        // Провал ниже зоны сбрасывает отсчёт.
        engine.ingest(bpm: 133, at: t0.addingTimeInterval(90))
        _ = engine.tick(at: t0.addingTimeInterval(90))
        for second in 91...126 {
            engine.ingest(bpm: 136, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertTrue(engine.isRegulating)
        XCTAssertGreaterThan(engine.cadence, 180, "в зоне подхода ритм растёт по одному")

        // После включения пульс ниже зоны уже не выключает регулятор.
        engine.ingest(bpm: 110, at: t0.addingTimeInterval(130))
        XCTAssertEqual(engine.tick(at: t0.addingTimeInterval(130))?.action, .speedUp(4))
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
        XCTAssertEqual(engine.cadence, 181)
        // Пульс прыгнул выше цели: сглаженный ещё около 136, решение принимается по сырому 160.
        engine.ingest(bpm: 160, at: t0.addingTimeInterval(6))
        XCTAssertLessThan(engine.smoothedHeartRate ?? 0, 140)
        XCTAssertEqual(engine.decisionHeartRate ?? 0, 160, accuracy: 0.001)
        let adjustment = engine.tick(at: t0.addingTimeInterval(10))
        XCTAssertEqual(adjustment?.action, .slowDown(1), "с 181 до нижней границы 180 только один шаг")
        XCTAssertEqual(engine.cadence, 180)
    }

    func testOverLimitArmsAfterDelayAtFloorAndClearsBelowTarget() {
        var s = settings
        s.cadenceMin = 180
        var engine = RegulatorEngine(settings: s)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertNil(engine.tick(at: t0))
        // Включаем регулятор и сразу перегружаем: ритм на нижней границе, пульс выше цели.
        engine.ingest(bpm: 165, at: t0.addingTimeInterval(5))
        _ = engine.tick(at: t0.addingTimeInterval(5))
        XCTAssertTrue(engine.isRegulating)
        XCTAssertEqual(engine.cadence, 180, "снижать уже некуда")
        XCTAssertFalse(engine.isOverLimit, "десять секунд ещё не прошло")
        for second in 6...14 {
            engine.ingest(bpm: 165, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertFalse(engine.isOverLimit)
        engine.ingest(bpm: 165, at: t0.addingTimeInterval(15))
        _ = engine.tick(at: t0.addingTimeInterval(15))
        XCTAssertTrue(engine.isOverLimit)

        // Пульс чуть ниже цели, но в пределах гистерезиса: предел держится.
        engine.ingest(bpm: 149, at: t0.addingTimeInterval(20))
        _ = engine.tick(at: t0.addingTimeInterval(20))
        XCTAssertTrue(engine.isOverLimit)
        // Опустился с запасом: предел снят.
        engine.ingest(bpm: 147, at: t0.addingTimeInterval(25))
        _ = engine.tick(at: t0.addingTimeInterval(25))
        XCTAssertFalse(engine.isOverLimit)
    }

    func testOverLimitNeedsFloorNotJustHighHeartRate() {
        var engine = RegulatorEngine(settings: settings)
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.reset(at: t0)
        XCTAssertNil(engine.tick(at: t0))
        // Разгоняем ритм до 192, потом пульс выше цели: ритм ещё есть куда снижать.
        for second in stride(from: 5, through: 20, by: 5) {
            engine.ingest(bpm: 120, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
        }
        engine.ingest(bpm: 135, at: t0.addingTimeInterval(25))
        _ = engine.tick(at: t0.addingTimeInterval(25))
        XCTAssertGreaterThan(engine.cadence, 180)
        for second in 26...45 {
            engine.ingest(bpm: 165, at: t0.addingTimeInterval(TimeInterval(second)))
            _ = engine.tick(at: t0.addingTimeInterval(TimeInterval(second)))
            if engine.cadence > 180 { XCTAssertFalse(engine.isOverLimit) }
        }
        XCTAssertEqual(engine.cadence, 180)
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
                                     smoothedHeartRate: 139.5, trendPerMinute: -1.25, decisionHeartRate: 139.5, metronome: 182,
                                     actualCadence: 178, distanceMeters: 3.2, speedMetersPerSecond: 3.1,
                                     groundContactMs: 240, verticalOscillationCm: 8.4, strideLengthMeters: 1.05,
                                     powerWatts: 250, efficiencyRecent: nil, warmup: true, decision: "a, b"))
        let csv = recorder.csv()
        XCTAssertTrue(csv.hasPrefix("# settings {"))
        XCTAssertTrue(csv.contains(TelemetryRecorder.header))
        XCTAssertTrue(csv.contains(",140,139.5,-1.2,139.5,182,178,3.2,3.10,240,8.4,1.05,250,,1,0,a; b"))
    }
}
