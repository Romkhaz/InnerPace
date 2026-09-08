import Foundation
import HealthKit
import Observation

/// Пульс покоя и возраст из Здоровья для зон и экономичности. Если Здоровье
/// ничего не даёт, остаются значения из настроек.
@Observable
final class HealthProfile {
    private(set) var restingHeartRate: Int?
    private(set) var age: Int?
    private let store = HKHealthStore()

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let resting = HKQuantityType(.restingHeartRate)
        let birth = HKCharacteristicType(.dateOfBirth)
        do {
            try await store.requestAuthorization(toShare: [], read: [resting, birth])
        } catch {
            return
        }
        if let components = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: components),
           let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year, years > 5 {
            age = years
        }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: resting, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
        if let sample {
            let unit = HKUnit.count().unitDivided(by: .minute())
            restingHeartRate = Int(sample.quantity.doubleValue(for: unit).rounded())
        }
    }

    /// Переносит найденное в настройки, если там другие значения.
    @MainActor
    func apply(to store: SettingsStore) {
        if let restingHeartRate, store.settings.restingHeartRate != restingHeartRate {
            store.settings.restingHeartRate = restingHeartRate
        }
        if let age, store.settings.age != age {
            store.settings.age = age
        }
    }
}
