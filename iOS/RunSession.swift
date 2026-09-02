import Foundation
import Observation

/// Ядро тренировки на телефоне: пульс с Polar, общий регулятор, метроном.
@MainActor
@Observable
final class RunSession {
    enum State: String {
        case idle, running, paused
    }

    enum HeartRateSource: String {
        case none = "—"
        case polar = "Polar H10"
    }

    struct Event: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    let settingsStore: SettingsStore
    let polar = PolarHeartRateMonitor()
    let metronome = Metronome()

    private(set) var state: State = .idle
    private(set) var cadence: Int
    private(set) var heartRate: Int?
    private(set) var heartRateSource: HeartRateSource = .none
    private(set) var elapsed: TimeInterval = 0
    private(set) var events: [Event] = []
    private(set) var lastError: String?

    private var engine: RegulatorEngine
    private var ticker: Timer?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let initialEngine = RegulatorEngine(settings: settingsStore.settings)
        engine = initialEngine
        cadence = initialEngine.cadence
        applySettingsToMetronome()

        polar.onHeartRate = { [weak self] bpm, time in
            self?.ingest(bpm: bpm, at: time)
        }
        polar.connect()
        startTicker()
    }

    var settings: RegulatorSettings { settingsStore.settings }
    var smoothedHeartRate: Double? { engine.smoothedHeartRate }

    /// Зона по сглаженному пульсу. Именно по ней принимает решение регулятор.
    var zone: HeartRateZone {
        guard let hr = smoothedHeartRate else { return .unknown }
        return HeartRateZone(heartRate: hr, settings: settings)
    }

    /// Зона по сырому пульсу с датчика.
    var rawZone: HeartRateZone {
        guard let hr = heartRate else { return .unknown }
        return HeartRateZone(heartRate: Double(hr), settings: settings)
    }

    // MARK: - Управление

    func start() {
        guard state == .idle else { return }
        engine.settings = settings
        engine.reset()
        cadence = engine.cadence
        accumulated = 0
        elapsed = 0
        events.removeAll()
        metronome.bpm = Double(cadence)
        guard startMetronome() else { return }
        segmentStart = Date()
        state = .running
        log(String(localized: "Старт. Каденс \(cadence)"))
    }

    func pause() {
        guard state == .running else { return }
        metronome.stop()
        if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        state = .paused
        log(String(localized: "Пауза"))
    }

    func resume() {
        guard state == .paused else { return }
        guard startMetronome() else { return }
        segmentStart = Date()
        engine.markResumed(at: Date())
        state = .running
        log(String(localized: "Продолжаем"))
    }

    func stop() {
        guard state != .idle else { return }
        metronome.stop()
        if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        elapsed = accumulated
        state = .idle
        log(String(localized: "Стоп. Итого \(formatElapsed(elapsed))"))
    }

    func toggleStartPause() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    /// Проверочный щелчок из настроек.
    func previewClick(_ on: Bool) {
        guard state == .idle else { return }
        if on {
            metronome.bpm = Double(settings.cadenceMin)
            _ = startMetronome()
        } else {
            metronome.stop()
        }
    }

    private func startMetronome() -> Bool {
        do {
            try metronome.start()
            lastError = nil
            return true
        } catch {
            lastError = String(localized: "Не удалось запустить звук: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Пульс

    private func ingest(bpm: Int, at time: Date) {
        heartRate = bpm
        heartRateSource = .polar
        engine.ingest(bpm: bpm, at: time)
    }

    // MARK: - Такт раз в секунду

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        syncSettings()
        if !engine.isHeartRateFresh(at: now) {
            heartRateSource = .none
        }
        guard state == .running else { return }
        if let segmentStart { elapsed = accumulated + now.timeIntervalSince(segmentStart) }
        guard let adjustment = engine.tick(at: now) else { return }
        cadence = adjustment.cadence
        metronome.bpm = Double(cadence)
        if let line = adjustment.logLine {
            log(line)
        }
    }

    private func syncSettings() {
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

    private func log(_ text: String) {
        events.insert(Event(time: Date(), text: text), at: 0)
        if events.count > 50 { events.removeLast() }
    }
}
