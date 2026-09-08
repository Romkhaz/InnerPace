import CoreMotion
import Foundation
import Observation

/// Фактический каденс, шаги, дистанция и темп от шагомера устройства.
/// На часах и на телефоне одинаково: CoreMotion считает всё сам.
@Observable
final class CadenceSensor {
    /// Текущий каденс, шагов в минуту.
    private(set) var cadence: Int?
    /// Шагов с начала тренировки.
    private(set) var steps: Int = 0
    /// Дистанция по шагомеру, метров. На телефоне это единственный источник дистанции.
    private(set) var distanceMeters: Double?
    /// Текущий темп по шагомеру, секунд на километр.
    private(set) var paceSecondsPerKm: Double?
    private(set) var isRunning = false
    /// Когда шагомер последний раз что-то присылал. На остановке обновления прекращаются,
    /// и последний каденс не должен считаться текущим.
    private(set) var lastUpdateAt: Date?
    /// На часах обновления приходят примерно раз в 10 с, поэтому порог с запасом.
    static let staleAfter: TimeInterval = 30

    private let pedometer = CMPedometer()

    static var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    func start(from date: Date) {
        guard CadenceSensor.isAvailable else { return }
        stop()
        cadence = nil
        lastUpdateAt = nil
        steps = 0
        distanceMeters = nil
        paceSecondsPerKm = nil
        isRunning = true
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let self, let data else { return }
            DispatchQueue.main.async {
                self.lastUpdateAt = Date()
                self.steps = data.numberOfSteps.intValue
                if let distance = data.distance { self.distanceMeters = distance.doubleValue }
                if let current = data.currentCadence {
                    self.cadence = Int((current.doubleValue * 60).rounded())
                }
                if let pace = data.currentPace, pace.doubleValue > 0 {
                    self.paceSecondsPerKm = pace.doubleValue * 1000
                }
            }
        }
    }

    /// Каденс для регулятора: ноль, если шагомер замолчал, то есть человек стоит.
    /// nil, пока шагомер ещё ничего не присылал.
    func currentCadence(at now: Date = Date()) -> Int? {
        guard let lastUpdateAt else { return nil }
        if now.timeIntervalSince(lastUpdateAt) > CadenceSensor.staleAfter { return 0 }
        return cadence
    }

    func stop() {
        guard isRunning else { return }
        pedometer.stopUpdates()
        isRunning = false
    }
}
