import Foundation
import WatchConnectivity

/// Отправляет итоги тренировок на телефон. Система сама доставит их,
/// когда телефон окажется рядом, даже если приложение на нём закрыто.
final class WatchSync: NSObject {
    private var pending: [WorkoutSummary] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ summary: WorkoutSummary) {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else {
            pending.append(summary)
            return
        }
        guard let data = summary.encoded() else { return }
        WCSession.default.transferUserInfo([SyncKeys.workout: data])
    }

    private func flush() {
        let queued = pending
        pending.removeAll()
        queued.forEach(send)
    }
}

extension WatchSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }
}

enum SyncKeys {
    static let workout = "workout"
}
