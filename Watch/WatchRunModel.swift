import Foundation
import Observation

/// Модель автономной тренировки на часах: тренировка HealthKit, регулятор, метроном.
@MainActor
@Observable
final class WatchRunModel {
    enum Phase {
        case setup, starting, running, paused, finishing
    }

    let settingsStore = SettingsStore()
    let workout = WatchWorkoutManager()
    let metronome = Metronome()

    private(set) var phase: Phase = .setup
    private(set) var cadence: Int
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var summary: String?
    private(set) var lastDecision: String?

    private var engine: RegulatorEngine
    private var ticker: Timer?

    init() {
        let initialEngine = RegulatorEngine(settings: settingsStore.settings)
        engine = initialEngine
        cadence = initialEngine.cadence
        workout.onHeartRate = { [weak self] bpm, time in
            self?.engine.ingest(bpm: bpm, at: time)
        }
        Task { await workout.requestAuthorization() }
    }

    var settings: RegulatorSettings { settingsStore.settings }
    var heartRate: Int? { workout.heartRate }
    var smoothedHeartRate: Double? { engine.smoothedHeartRate }
    var distanceMeters: Double { workout.distanceMeters }
    var paceSecondsPerKm: Double? { workout.paceSecondsPerKm }
    var isActive: Bool { phase == .running || phase == .paused }

    var zone: HeartRateZone {
        guard let hr = smoothedHeartRate else { return .unknown }
        return HeartRateZone(heartRate: hr, settings: settings)
    }

    var errorText: String? {
        lastError ?? workout.lastError
    }

    func start() async {
        guard phase == .setup else { return }
        phase = .starting
        lastError = nil
        summary = nil
        lastDecision = nil

        engine.settings = settings
        engine.reset()
        cadence = engine.cadence
        metronome.volume = Float(settings.clickVolume)
        metronome.halfTime = settings.halfTimeClick
        metronome.bpm = Double(cadence)

        do {
            try await metronome.start()
        } catch {
            lastError = error.localizedDescription
            phase = .setup
            return
        }
        do {
            try await workout.start()
        } catch {
            metronome.stop()
            lastError = error.localizedDescription
            phase = .setup
            return
        }
        elapsed = 0
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running else { return }
        workout.pause()
        metronome.stop()
        phase = .paused
    }

    func resume() async {
        guard phase == .paused else { return }
        do {
            try await metronome.start()
        } catch {
            lastError = error.localizedDescription
            return
        }
        workout.resume()
        engine.markResumed(at: Date())
        phase = .running
    }

    func togglePause() async {
        if phase == .running {
            pause()
        } else {
            await resume()
        }
    }

    func end() async {
        guard isActive else { return }
        phase = .finishing
        metronome.stop()
        ticker?.invalidate()
        ticker = nil
        let finalElapsed = workout.elapsed
        let finalDistance = workout.distanceMeters
        await workout.end()
        summary = "\(formatDistance(finalDistance)) за \(formatElapsed(finalElapsed))"
        elapsed = finalElapsed
        phase = .setup
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        elapsed = workout.elapsed
        guard phase == .running else { return }
        guard let adjustment = engine.tick(at: Date()) else { return }
        cadence = adjustment.cadence
        metronome.bpm = Double(cadence)
        if let line = adjustment.logLine {
            lastDecision = line
        }
    }
}
