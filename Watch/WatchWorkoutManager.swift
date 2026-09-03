import CoreLocation
import Foundation
import HealthKit
import Observation

/// Тренировка на часах: сессия HealthKit держит приложение живым в фоне,
/// отдаёт пульс, дистанцию, скорость и беговые метрики, пишет маршрут по GPS
/// и сохраняет пробежку в Здоровье как обычную тренировку.
@Observable
final class WatchWorkoutManager: NSObject {
    private(set) var isActive = false
    private(set) var heartRate: Int?
    private(set) var distanceMeters: Double = 0
    private(set) var speedMetersPerSecond: Double?
    private(set) var groundContactMs: Double?
    private(set) var verticalOscillationCm: Double?
    private(set) var strideLengthMeters: Double?
    private(set) var routePointCount = 0
    private(set) var lastError: String?

    /// Вызывается на главной очереди на каждый новый отсчёт пульса.
    var onHeartRate: ((Int, Date) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    private var endContinuation: CheckedContinuation<Void, Never>?

    /// Что читаем и что записываем в тренировку. Без разрешения на запись HealthKit
    /// молча выбрасывает собранные метрики, и Фитнес их не показывает.
    private static let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .heartRate, .distanceWalkingRunning, .activeEnergyBurned, .stepCount,
        .runningSpeed, .runningPower, .runningStrideLength,
        .runningVerticalOscillation, .runningGroundContactTime,
    ]
    private static let writableIdentifiers: [HKQuantityTypeIdentifier] = [
        .distanceWalkingRunning, .activeEnergyBurned, .stepCount,
        .runningSpeed, .runningPower, .runningStrideLength,
        .runningVerticalOscillation, .runningGroundContactTime,
    ]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
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

    func averageHeartRate() -> Double? {
        average(of: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    func averageGroundContactMs() -> Double? {
        average(of: .runningGroundContactTime, unit: HKUnit.secondUnit(with: .milli))
    }

    func averageVerticalOscillationCm() -> Double? {
        average(of: .runningVerticalOscillation, unit: HKUnit.meterUnit(with: .centi))
    }

    private func average(of identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
        guard let builder,
              let statistics = builder.statistics(for: HKQuantityType(identifier)),
              let quantity = statistics.averageQuantity() else { return nil }
        return quantity.doubleValue(for: unit)
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id in WatchWorkoutManager.writableIdentifiers { share.insert(HKQuantityType(id)) }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        for id in WatchWorkoutManager.quantityIdentifiers { read.insert(HKQuantityType(id)) }
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
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        for id in WatchWorkoutManager.quantityIdentifiers where id != .heartRate {
            dataSource.enableCollection(for: HKQuantityType(id), predicate: nil)
        }
        builder.dataSource = dataSource
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
            groundContactMs = nil
            verticalOscillationCm = nil
            strideLengthMeters = nil
            routePointCount = 0
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
        var problems: [String] = []
        var savedWorkout: HKWorkout?
        do {
            try await builder?.endCollection(at: date)
            savedWorkout = try await builder?.finishWorkout()
        } catch {
            problems.append(String(localized: "Сохранение: \(error.localizedDescription)"))
        }
        if let workout = savedWorkout, let routeBuilder, routePointCount > 0 {
            do {
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            } catch {
                problems.append(String(localized: "Маршрут: \(error.localizedDescription)"))
            }
        } else if savedWorkout != nil, routePointCount == 0 {
            problems.append(String(localized: "Маршрут: GPS не дал ни одной точки"))
        }
        let problemText = problems.isEmpty ? nil : problems.joined(separator: "\n")
        await MainActor.run {
            isActive = false
            if let problemText { lastError = problemText }
        }
        session = nil
        builder = nil
        self.routeBuilder = nil
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
        var newContact: Double?
        var newOscillation: Double?
        var newStride: Double?

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType {
            case HKQuantityType(.heartRate):
                if let q = statistics.mostRecentQuantity() {
                    newHeartRate = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
                }
            case HKQuantityType(.distanceWalkingRunning):
                if let q = statistics.sumQuantity() { newDistance = q.doubleValue(for: .meter()) }
            case HKQuantityType(.runningSpeed):
                if let q = statistics.mostRecentQuantity() {
                    newSpeed = q.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
                }
            case HKQuantityType(.runningGroundContactTime):
                if let q = statistics.mostRecentQuantity() { newContact = q.doubleValue(for: HKUnit.secondUnit(with: .milli)) }
            case HKQuantityType(.runningVerticalOscillation):
                if let q = statistics.mostRecentQuantity() { newOscillation = q.doubleValue(for: HKUnit.meterUnit(with: .centi)) }
            case HKQuantityType(.runningStrideLength):
                if let q = statistics.mostRecentQuantity() { newStride = q.doubleValue(for: .meter()) }
            default:
                break
            }
        }

        DispatchQueue.main.async {
            if let newHeartRate, newHeartRate > 0 {
                self.heartRate = newHeartRate
                self.onHeartRate?(newHeartRate, Date())
            }
            if let newDistance { self.distanceMeters = newDistance }
            if let newSpeed { self.speedMetersPerSecond = newSpeed }
            if let newContact { self.groundContactMs = newContact }
            if let newOscillation { self.verticalOscillationCm = newOscillation }
            if let newStride { self.strideLengthMeters = newStride }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let accurate = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !accurate.isEmpty, let routeBuilder else { return }
        routeBuilder.insertRouteData(accurate) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.routePointCount += accurate.count
                } else if let error {
                    self.lastError = String(localized: "Маршрут: \(error.localizedDescription)")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = String(localized: "GPS: \(error.localizedDescription)")
        }
    }
}
