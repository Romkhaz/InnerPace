import Foundation
import Observation

/// Модель автономной тренировки на часах: тренировка HealthKit, регулятор,
/// метроном, шагомер, эффективность, отчёт и телеметрия.
@MainActor
@Observable
final class WatchRunModel {
    enum Phase {
        case setup, starting, running, paused, finishing, report
    }

    let settingsStore = SettingsStore()
    let workout = WatchWorkoutManager()
    let metronome = Metronome()
    let pedometer = CadenceSensor()
    let store = WorkoutStore()
    private let sync = WatchSync()

    private(set) var phase: Phase = .setup
    private(set) var cadence: Int
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var lastDecision: String?
    private(set) var report: WorkoutSummary?

    private var engine: RegulatorEngine
    private var efficiency = EfficiencyTracker()
    private var telemetry = TelemetryRecorder()
    private let cues = CueCoordinator()
    private var ticker: Timer?
    private var startDate: Date?
    private var metronomeSum = 0
    private var metronomeCount = 0

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
    var actualCadence: Int? { pedometer.cadence }
    var groundContactMs: Double? { workout.groundContactMs }
    var verticalOscillationCm: Double? { workout.verticalOscillationCm }
    var recentEfficiency: Double? { efficiency.recent }
    var isActive: Bool { phase == .running || phase == .paused }


    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 50, elapsed > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    var zone: HeartRateZone {
        guard let hr = smoothedHeartRate else { return .unknown }
        return HeartRateZone(heartRate: hr, settings: settings)
    }

    var errorText: String? {
        lastError ?? workout.lastError
    }

    // MARK: - Управление

    func start() async {
        guard phase == .setup else { return }
        phase = .starting
        lastError = nil
        lastDecision = nil
        report = nil

        let now = Date()
        engine.settings = settings
        engine.reset(at: now)
        cadence = engine.cadence
        efficiency.reset()
        telemetry.start(settings: settings)
        cues.reset()
        metronome.warning = false
        metronomeSum = 0
        metronomeCount = 0
        applySettingsToMetronome()
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
        pedometer.start(from: now)
        startDate = now
        elapsed = 0
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running else { return }
        workout.pause()
        metronome.stop()
        engine.markPaused(at: Date())
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
        applySettings()
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
        metronome.warning = false
        metronome.stop()
        ticker?.invalidate()
        ticker = nil
        pedometer.stop()

        let finalElapsed = workout.elapsed
        let finalDistance = workout.distanceMeters
        let averageHeartRate = workout.averageHeartRate()
        let averageContact = workout.averageGroundContactMs()
        let averageOscillation = workout.averageVerticalOscillationCm()
        let averageCadence: Double? = finalElapsed > 30 && pedometer.steps > 0 ? Double(pedometer.steps) / (finalElapsed / 60) : nil
        let averageMetronome: Double? = metronomeCount > 0 ? Double(metronomeSum) / Double(metronomeCount) : nil

        await workout.end()

        let summary = WorkoutSummary(
            date: startDate ?? Date(),
            duration: finalElapsed,
            distanceMeters: finalDistance,
            averageHeartRate: averageHeartRate,
            averageCadence: averageCadence,
            averageMetronome: averageMetronome,
            efficiencyMetersPerBeat: efficiency.total,
            averageGroundContactMs: averageContact,
            averageVerticalOscillationCm: averageOscillation,
            source: .watch
        )
        store.add(summary)
        sync.send(summary)
        if settings.developerMode, let url = telemetry.write(date: summary.date, source: .watch) {
            sync.send(file: url)
        }
        report = summary
        elapsed = finalElapsed
        phase = .report
    }

    func dismissReport() {
        report = nil
        phase = .setup
    }

    // MARK: - Настройки на бегу

    /// Настройки применяются сразу, и на бегу, и на паузе.
    private func applySettings() {
        if engine.settings != settings {
            engine.settings = settings
            cadence = engine.cadence
            metronome.bpm = Double(cadence)
        }
        applySettingsToMetronome()
    }

    private func applySettingsToMetronome() {
        metronome.volume = Float(settings.clickVolume)
        metronome.halfTime = settings.halfTimeClick
    }

    // MARK: - Такт

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        elapsed = workout.elapsed
        guard phase == .running else { return }
        applySettings()
        efficiency.update(time: now, distance: workout.distanceMeters,
                          heartRate: smoothedHeartRate ?? heartRate.map(Double.init))
        metronomeSum += cadence
        metronomeCount += 1
        var decision: String?
        if let adjustment = engine.tick(at: now) {
            cadence = adjustment.cadence
            metronome.bpm = Double(cadence)
            if let line = adjustment.logLine {
                lastDecision = line
                decision = line
            }
        }
        metronome.warning = engine.isOverLimit
        if let cue = cues.update(overLimit: engine.isOverLimit, settings: settings, now: now) {
            lastDecision = cue
            decision = cue
        }
        if settings.developerMode {
            telemetry.append(TelemetryRow(
                time: now, elapsed: elapsed, heartRate: heartRate,
                smoothedHeartRate: smoothedHeartRate, decisionHeartRate: engine.decisionHeartRate,
                metronome: cadence, actualCadence: actualCadence,
                distanceMeters: workout.distanceMeters, speedMetersPerSecond: workout.speedMetersPerSecond,
                groundContactMs: groundContactMs, verticalOscillationCm: verticalOscillationCm,
                strideLengthMeters: workout.strideLengthMeters, powerWatts: workout.powerWatts,
                efficiencyRecent: efficiency.recent, warmup: !engine.isRegulating, overLimit: engine.isOverLimit, decision: decision
            ))
        }
    }
}
