import Foundation
import WatchConnectivity

/// Принимает итоги тренировок и файлы телеметрии с часов.
final class PhoneSync: NSObject {
    /// Вызывается на главной очереди.
    var onWorkout: ((WorkoutSummary) -> Void)?
    var onTelemetryFile: ((URL) -> Void)?

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

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Файл живёт только до конца вызова, переносим его в папку телеметрии сразу.
        let name = (file.metadata?[SyncKeys.telemetry] as? String) ?? file.fileURL.lastPathComponent
        let target = TelemetryRecorder.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        guard (try? FileManager.default.moveItem(at: file.fileURL, to: target)) != nil
            || (try? FileManager.default.copyItem(at: file.fileURL, to: target)) != nil else { return }
        DispatchQueue.main.async {
            self.onTelemetryFile?(target)
        }
    }
}

enum SyncKeys {
    static let workout = "workout"
    static let telemetry = "telemetry"
}
