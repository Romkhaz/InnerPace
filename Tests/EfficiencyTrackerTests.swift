import XCTest

final class EfficiencyTrackerTests: XCTestCase {
    func testTotalAndRecentEfficiency() {
        var tracker = EfficiencyTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        // 3 м/с при пульсе 150: 2,5 удара в секунду → 1,2 м на удар.
        for second in 0...200 {
            tracker.update(time: t0.addingTimeInterval(TimeInterval(second)),
                           distance: Double(second) * 3, heartRate: 150)
        }
        XCTAssertEqual(tracker.total ?? 0, 1.2, accuracy: 0.05)
        XCTAssertEqual(tracker.recent ?? 0, 1.2, accuracy: 0.05)
    }

    func testRecentReactsToPaceChange() {
        var tracker = EfficiencyTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        var distance = 0.0
        for second in 0...300 {
            // Первые 150 секунд бежим 3 м/с, потом 2 м/с при том же пульсе.
            distance += second < 150 ? 3 : 2
            tracker.update(time: t0.addingTimeInterval(TimeInterval(second)), distance: distance, heartRate: 150)
        }
        XCTAssertEqual(tracker.recent ?? 0, 0.8, accuracy: 0.05)
        XCTAssertGreaterThan(tracker.total ?? 0, 0.9)
    }

    func testNoValueWithoutHeartRate() {
        var tracker = EfficiencyTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        for second in 0...100 {
            tracker.update(time: t0.addingTimeInterval(TimeInterval(second)), distance: Double(second) * 3, heartRate: nil)
        }
        XCTAssertNil(tracker.total)
        XCTAssertNil(tracker.recent)
    }
}
