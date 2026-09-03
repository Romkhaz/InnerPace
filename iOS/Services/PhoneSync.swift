import Foundation
import WatchConnectivity

/// Принимает итоги тренировок с часов.
final class PhoneSync: NSObject {
    /// Вызывается на главной очереди.
    var onWorkout: ((WorkoutSummary) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension PhoneSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[SyncKeys.workout] as? Data,
              let summary = WorkoutSummary.decode(data) else { return }
        DispatchQueue.main.async {
            self.onWorkout?(summary)
        }
    }
}

enum SyncKeys {
    static let workout = "workout"
}
