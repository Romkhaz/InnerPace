import Foundation

/// Итог тренировки. Хранится на устройстве и пересылается с часов на телефон.
struct WorkoutSummary: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case watch, phone
    }

    var id: UUID = UUID()
    var date: Date
    var duration: TimeInterval
    var distanceMeters: Double
    var averageHeartRate: Double?
    /// Фактический каденс, шагов в минуту.
    var averageCadence: Double?
    /// Средний ритм метронома, ударов в минуту.
    var averageMetronome: Double?
    /// Метров на один удар сердца за всю тренировку.
    var efficiencyMetersPerBeat: Double?
    var averageGroundContactMs: Double?
    var averageVerticalOscillationCm: Double?
    var source: Source

    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 50, duration > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> WorkoutSummary? {
        try? JSONDecoder().decode(WorkoutSummary.self, from: data)
    }
}

/// Хранилище итогов тренировок в файле приложения.
@Observable
final class WorkoutStore {
    private(set) var workouts: [WorkoutSummary] = []
    private let fileURL: URL

    init(fileName: String = "workouts.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(fileName)
        load()
    }

    func add(_ summary: WorkoutSummary) {
        if let index = workouts.firstIndex(where: { $0.id == summary.id }) {
            workouts[index] = summary
        } else {
            workouts.append(summary)
        }
        workouts.sort { $0.date > $1.date }
        save()
    }

    func remove(_ summary: WorkoutSummary) {
        workouts.removeAll { $0.id == summary.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([WorkoutSummary].self, from: data) else { return }
        workouts = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(workouts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
