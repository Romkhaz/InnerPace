import XCTest

final class CadenceControllerTests: XCTestCase {
    private var settings: RegulatorSettings {
        var s = RegulatorSettings.default
        s.cadenceMin = 180
        s.cadenceMax = 200
        s.heartRateMin = 130
        s.heartRateMax = 150
        s.holdBand = 3
        s.maxStep = 4
        return s
    }

    func testStartsAtLowerCadence() {
        let controller = CadenceController(settings: settings)
        XCTAssertEqual(controller.cadence, 180)
    }

    func testLowHeartRateSpeedsUpWithMaxStep() {
        var controller = CadenceController(settings: settings)
        XCTAssertEqual(controller.adjust(forHeartRate: 130), .speedUp(4))
        XCTAssertEqual(controller.cadence, 184)
        XCTAssertEqual(controller.adjust(forHeartRate: 120), .speedUp(4))
        XCTAssertEqual(controller.cadence, 188)
    }

    func testStepShrinksNearTarget() {
        var controller = CadenceController(settings: settings)
        XCTAssertEqual(controller.adjust(forHeartRate: 140), .speedUp(2))
        XCTAssertEqual(controller.adjust(forHeartRate: 145), .speedUp(1))
    }

    func testHoldBandBelowTarget() {
        var controller = CadenceController(settings: settings)
        XCTAssertEqual(controller.adjust(forHeartRate: 148), .hold)
        XCTAssertEqual(controller.adjust(forHeartRate: 150), .hold)
        XCTAssertEqual(controller.cadence, 180)
    }

    func testHighHeartRateSlowsDown() {
        var controller = CadenceController(settings: settings)
        _ = controller.adjust(forHeartRate: 120)
        _ = controller.adjust(forHeartRate: 120)
        XCTAssertEqual(controller.cadence, 188)
        XCTAssertEqual(controller.adjust(forHeartRate: 152), .slowDown(1))
        XCTAssertEqual(controller.adjust(forHeartRate: 160), .slowDown(2))
        XCTAssertEqual(controller.adjust(forHeartRate: 175), .slowDown(4))
        XCTAssertEqual(controller.cadence, 181)
    }

    func testClampsToRange() {
        var controller = CadenceController(settings: settings)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 100) }
        XCTAssertEqual(controller.cadence, 200)
        XCTAssertEqual(controller.adjust(forHeartRate: 100), .hold)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 190) }
        XCTAssertEqual(controller.cadence, 180)
        XCTAssertEqual(controller.adjust(forHeartRate: 190), .hold)
    }

    func testSettingsChangeClampsCadence() {
        var controller = CadenceController(settings: settings)
        for _ in 0..<10 { _ = controller.adjust(forHeartRate: 100) }
        var narrower = settings
        narrower.cadenceMax = 190
        controller.settings = narrower
        XCTAssertEqual(controller.cadence, 190)
    }

    func testUserScenario() {
        // Начинаем на 180 при пульсе 130, разгоняемся к 150, потом горка и пульс 160.
        var controller = CadenceController(settings: settings)
        var hr = 130.0
        var steps = 0
        while controller.cadence < 200, steps < 20 {
            _ = controller.adjust(forHeartRate: hr)
            hr = min(150, hr + 3)
            steps += 1
        }
        XCTAssertGreaterThan(controller.cadence, 180)
        let peak = controller.cadence
        for _ in 0..<5 { _ = controller.adjust(forHeartRate: 160) }
        XCTAssertLessThan(controller.cadence, peak)
    }
}
