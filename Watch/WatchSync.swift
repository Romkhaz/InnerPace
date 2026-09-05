import Foundation
import WatchConnectivity

/// Отправляет итоги тренировок и файлы телеметрии на телефон. Система сама
/// доставит их, когда телефон окажется рядом, даже если приложение на нём закрыто.
final class WatchSync: NSObject {
    private var pendingSummaries: [WorkoutSummary] = []
    private var pendingFiles: [URL] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ summary: WorkoutSummary) {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else {
            pendingSummaries.append(summary)
            return
        }
        guard let data = summary.encoded() else { return }
        WCSession.default.transferUserInfo([SyncKeys.workout: data])
    }

    func send(file url: URL) {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else {
            pendingFiles.append(url)
            return
        }
        WCSession.default.transferFile(url, metadata: [SyncKeys.telemetry: url.lastPathComponent])
    }

    private func flush() {
        let summaries = pendingSummaries
        pendingSummaries.removeAll()
        summaries.forEach(send)
        let files = pendingFiles
        pendingFiles.removeAll()
        files.forEach { send(file: $0) }
    }
}

extension WatchSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }
}

enum SyncKeys {
    static let workout = "workout"
    static let telemetry = "telemetry"
}
