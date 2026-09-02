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
}
