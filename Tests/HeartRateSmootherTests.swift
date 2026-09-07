import XCTest

final class HeartRateSmootherTests: XCTestCase {
    func testFirstSampleIsPassedThrough() {
        var smoother = HeartRateSmoother(timeConstant: 10)
        XCTAssertEqual(smoother.add(140, at: Date(timeIntervalSince1970: 0)), 140)
    }

    func testMovesTowardNewValueWithLag() {
        var smoother = HeartRateSmoother(timeConstant: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        smoother.add(140, at: t0)
        let next = smoother.add(160, at: t0.addingTimeInterval(1))
        XCTAssertGreaterThan(next, 140)
        XCTAssertLessThan(next, 145)
        var later = next
        for second in 2...60 {
            later = smoother.add(160, at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(later, 160, accuracy: 0.2)
    }

    func testZeroTimeConstantDisablesSmoothing() {
        var smoother = HeartRateSmoother(timeConstant: 0)
        let t0 = Date(timeIntervalSince1970: 0)
        smoother.add(140, at: t0)
        XCTAssertEqual(smoother.add(160, at: t0.addingTimeInterval(1)), 160)
    }

    func testResetForgetsHistory() {
        var smoother = HeartRateSmoother(timeConstant: 10)
        smoother.add(140)
        smoother.reset()
        XCTAssertNil(smoother.value)
        XCTAssertEqual(smoother.add(100), 100)
    }

    func testTrendSlopeAndWarmup() {
        var trend = HeartRateTrend(window: 20)
        let t0 = Date(timeIntervalSince1970: 0)
        trend.add(130, at: t0)
        trend.add(131, at: t0.addingTimeInterval(5))
        XCTAssertEqual(trend.slopePerMinute, 0, "меньше половины окна: тренда ещё нет")
        for second in stride(from: 10, through: 40, by: 5) {
            trend.add(130 + Double(second) * 0.2, at: t0.addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(trend.slopePerMinute, 12, accuracy: 0.01, "0,2 удара в секунду это 12 в минуту")
        trend.reset()
        XCTAssertEqual(trend.slopePerMinute, 0)
    }
}
