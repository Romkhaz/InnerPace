import XCTest

final class CadenceControllerTests: XCTestCase {
    /// Настройки без зоны подхода и с симметричным шагом, чтобы проверять базовую пропорцию.
    private var plain: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMin = 130
        s.heartRateMax = 150
        s.holdBand = 3
        s.approachPercent = 0
        s.slowdownFactor = 1
        s.maxStep = 4
        return s
    }

    func testStartsAtLowerCadence() {
        let controller = CadenceController(settings: plain)
        XCTAssertEqual(controller.cadence, 180)
    }

    func testLowHeartRateSpeedsUpWithMaxStep() {
        var controller = CadenceController(settings: plain)
        XCTAssertEqual(controller.adjust(forHeartRate: 130), .speedUp(4))
        XCTAssertEqual(controller.cadence, 184)
        XCTAssertEqual(controller.adjust(forHeartRate: 120), .speedUp(4))
        XCTAssertEqual(controller.cadence, 188)
    }

    func testStepShrinksNearTarget() {
        var controller = CadenceController(settings: plain)
        XCTAssertEqual(controller.adjust(forHeartRate: 140), .speedUp(2))
        XCTAssertEqual(controller.adjust(forHeartRate: 145), .speedUp(1))
    }

    func testHoldBandBelowTarget() {
        var controller = CadenceController(settings: plain)
        XCTAssertEqual(controller.adjust(forHeartRate: 148), .hold)
        XCTAssertEqual(controller.adjust(forHeartRate: 150), .hold)
        XCTAssertEqual(controller.cadence, 180)
    }

    func testHighHeartRateSlowsDownRoundingUp() {
        var controller = CadenceController(settings: plain)
        controller.setCadence(190)
        XCTAssertEqual(controller.adjust(forHeartRate: 151), .slowDown(1))
        XCTAssertEqual(controller.adjust(forHeartRate: 156), .slowDown(2), "1,2 шага округляем вверх до 2")
        XCTAssertEqual(controller.adjust(forHeartRate: 175), .slowDown(4))
        XCTAssertEqual(controller.cadence, 183)
    }

    func testClampsToRange() {
        var controller = CadenceController(settings: plain)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 100) }
        XCTAssertEqual(controller.cadence, 200)
        XCTAssertEqual(controller.adjust(forHeartRate: 100), .hold)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 190) }
        XCTAssertEqual(controller.cadence, 180)
        XCTAssertEqual(controller.adjust(forHeartRate: 190), .hold)
    }

    func testSettingsChangeClampsCadence() {
        var controller = CadenceController(settings: plain)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 100) }
        var narrower = plain
        narrower.cadenceMax = 190
        controller.settings = narrower
        XCTAssertEqual(controller.cadence, 190)
    }

    // MARK: - Зона подхода и ускоренное снижение

    func testApproachZoneGrowsByOneStep() {
        var s = plain
        s.approachPercent = 10   // подход с 135
        s.holdBand = 8           // удержание с 142
        var controller = CadenceController(settings: s)
        XCTAssertEqual(controller.adjust(forHeartRate: 130), .speedUp(4))
        XCTAssertEqual(controller.adjust(forHeartRate: 136), .speedUp(1))
        XCTAssertEqual(controller.adjust(forHeartRate: 141), .speedUp(1))
        XCTAssertEqual(controller.adjust(forHeartRate: 142), .hold)
        XCTAssertEqual(controller.adjust(forHeartRate: 149), .hold)
        XCTAssertEqual(controller.adjust(forHeartRate: 151), .slowDown(1))
    }

    func testSlowdownFactorMakesDescentFaster() {
        var s = plain
        s.slowdownFactor = 3
        var controller = CadenceController(settings: s)
        controller.setCadence(200)
        // При симметрии было бы −2, с множителем 3 получаем −6.
        XCTAssertEqual(controller.adjust(forHeartRate: 160), .slowDown(6))
        // Потолок снижения тоже в три раза выше максимального шага.
        XCTAssertEqual(controller.adjust(forHeartRate: 190), .slowDown(12))
        XCTAssertEqual(controller.cadence, 182)
    }

    func testSlowdownFactorTenDropsToFloorInOneStep() {
        var s = plain
        s.slowdownFactor = 10
        var controller = CadenceController(settings: s)
        controller.setCadence(200)
        // 4 удара выше цели: 4 × 0,2 × 10 = 8 ударов вниз за один интервал.
        XCTAssertEqual(controller.adjust(forHeartRate: 154), .slowDown(8))
        XCTAssertEqual(controller.adjust(forHeartRate: 163), .slowDown(12))
        XCTAssertEqual(controller.cadence, 180)
    }

    func testDerivedCadenceMaxAndZoneWidth() {
        var s = RegulatorSettings.default
        s.setCadenceMinDerivingMax(180)
        XCTAssertEqual(s.cadenceMax, 207)
        s.setTargetHeartRateKeepingZoneWidth(160)
        XCTAssertEqual(s.heartRateMax, 160)
        XCTAssertEqual(s.heartRateMin, 140)
    }
}
