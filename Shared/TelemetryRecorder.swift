import Foundation

/// Посекундная телеметрия тренировки для режима разработчика. Пишется в CSV.
struct TelemetryRow {
    var time: Date
    var elapsed: TimeInterval
    var heartRate: Int?
    var smoothedHeartRate: Double?
    var decisionHeartRate: Double?
    var metronome: Int
    var actualCadence: Int?
    var distanceMeters: Double
    var speedMetersPerSecond: Double?
    var groundContactMs: Double?
    var verticalOscillationCm: Double?
    var strideLengthMeters: Double?
    var powerWatts: Double?
    var efficiencyRecent: Double?
    var warmup: Bool
    var decision: String?
}

struct TelemetryRecorder {
    private(set) var rows: [TelemetryRow] = []
    private(set) var settingsLine: String = ""

    static let header = "time,elapsed_s,hr,hr_smoothed,hr_decision,metronome_bpm,cadence_spm,distance_m,speed_mps,gct_ms,vo_cm,stride_m,power_w,efficiency_m_per_beat,warmup,decision"

    mutating func start(settings: RegulatorSettings) {
        rows.removeAll()
        if let data = try? JSONEncoder().encode(settings), let json = String(data: data, encoding: .utf8) {
            settingsLine = "# settings " + json.replacingOccurrences(of: "\n", with: " ")
        }
    }

    mutating func append(_ row: TelemetryRow) {
        rows.append(row)
    }

    var isEmpty: Bool { rows.isEmpty }

    func csv() -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines: [String] = [settingsLine, TelemetryRecorder.header]
        for r in rows {
            let fields: [String] = [
                iso.string(from: r.time),
                String(format: "%.0f", r.elapsed),
                r.heartRate.map(String.init) ?? "",
                r.smoothedHeartRate.map { String(format: "%.1f", $0) } ?? "",
                r.decisionHeartRate.map { String(format: "%.1f", $0) } ?? "",
                String(r.metronome),
                r.actualCadence.map(String.init) ?? "",
                String(format: "%.1f", r.distanceMeters),
                r.speedMetersPerSecond.map { String(format: "%.2f", $0) } ?? "",
                r.groundContactMs.map { String(format: "%.0f", $0) } ?? "",
                r.verticalOscillationCm.map { String(format: "%.1f", $0) } ?? "",
                r.strideLengthMeters.map { String(format: "%.2f", $0) } ?? "",
                r.powerWatts.map { String(format: "%.0f", $0) } ?? "",
                r.efficiencyRecent.map { String(format: "%.3f", $0) } ?? "",
                r.warmup ? "1" : "0",
                (r.decision ?? "").replacingOccurrences(of: ",", with: ";"),
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Папка телеметрии в Documents: на телефоне она видна в приложении «Файлы».
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Telemetry", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for date: Date, source: WorkoutSummary.Source) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "innerpace_\(formatter.string(from: date))_\(source.rawValue).csv"
    }

    /// Сохраняет CSV и возвращает путь к файлу.
    func write(date: Date, source: WorkoutSummary.Source) -> URL? {
        guard !rows.isEmpty else { return nil }
        let url = TelemetryRecorder.directory.appendingPathComponent(TelemetryRecorder.fileName(for: date, source: source))
        do {
            try csv().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func savedFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))
            ?? []
        return urls.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
