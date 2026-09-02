import CoreLocation
import Foundation
import HealthKit
import Observation

/// Тренировка на часах: сессия HealthKit держит приложение живым в фоне,
/// отдаёт пульс, дистанцию и скорость, пишет маршрут по GPS и сохраняет
/// пробежку в Здоровье как обычную тренировку.
@Observable
final class WatchWorkoutManager: NSObject {
    private(set) var isActive = false
    private(set) var heartRate: Int?
    private(set) var distanceMeters: Double = 0
    private(set) var speedMetersPerSecond: Double?
    private(set) var lastError: String?

    /// Вызывается на главной очереди на каждый новый отсчёт пульса.
    var onHeartRate: ((Int, Date) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    private var endContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    /// Текущий темп, секунд на километр. Ниже 0,3 м/с считаем, что стоим.
    var paceSecondsPerKm: Double? {
        guard let speed = speedMetersPerSecond, speed > 0.3 else { return nil }
        return 1000 / speed
    }

    /// Время тренировки без пауз, его ведёт сам HealthKit.
    var elapsed: TimeInterval {
        builder?.elapsedTime ?? 0
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.activeEnergyBurned),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
        locationManager.requestWhenInUseAuthorization()
    }

    func start() async throws {
        guard !isActive else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)
        // Без фонового режима location этот флаг роняет приложение проверкой CoreLocation.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        locationManager.startUpdatingLocation()

        await MainActor.run {
            heartRate = nil
            distanceMeters = 0
            speedMetersPerSecond = nil
            isActive = true
            lastError = nil
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Завершает тренировку и ждёт, пока она сохранится в Здоровье.
    func end() async {
        guard let session, session.state != .ended else { return }
        await withCheckedContinuation { continuation in
            endContinuation = continuation
            session.end()
        }
    }

    private func finish(at date: Date) async {
        locationManager.stopUpdatingLocation()
        do {
            try await builder?.endCollection(at: date)
            if let workout = try await builder?.finishWorkout() {
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
        await MainActor.run { isActive = false }
        session = nil
        builder = nil
        routeBuilder = nil
        endContinuation?.resume()
        endContinuation = nil
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { await finish(at: date) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var newHeartRate: Int?
        var newDistance: Double?
        var newSpeed: Double?

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            if quantityType == HKQuantityType(.heartRate) {
                if let quantity = statistics.mostRecentQuantity() {
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    newHeartRate = Int(quantity.doubleValue(for: unit).rounded())
                }
            } else if quantityType == HKQuantityType(.distanceWalkingRunning) {
                if let quantity = statistics.sumQuantity() {
                    newDistance = quantity.doubleValue(for: .meter())
                }
            } else if quantityType == HKQuantityType(.runningSpeed) {
                if let quantity = statistics.mostRecentQuantity() {
                    let unit = HKUnit.meter().unitDivided(by: .second())
                    newSpeed = quantity.doubleValue(for: unit)
                }
            }
        }

        DispatchQueue.main.async {
            if let newHeartRate, newHeartRate > 0 {
                self.heartRate = newHeartRate
                self.onHeartRate?(newHeartRate, Date())
            }
            if let newDistance { self.distanceMeters = newDistance }
            if let newSpeed { self.speedMetersPerSecond = newSpeed }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let accurate = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !accurate.isEmpty, let routeBuilder else { return }
        routeBuilder.insertRouteData(accurate) { _, _ in }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
