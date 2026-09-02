import AVFoundation
import Foundation
import os

enum MetronomeError: LocalizedError {
    case noHeadphones

    var errorDescription: String? {
        switch self {
        case .noHeadphones: return String(localized: "Подключите Bluetooth-наушники к часам")
        }
    }
}

/// Метроном на AVAudioSourceNode: щелчок синтезируется прямо в аудиопотоке,
/// поэтому темп меняется мгновенно и не плывёт. Один код для телефона и часов,
/// отличается только настройка аудиосессии.
final class Metronome {
    private struct Params {
        var bpm: Double = 180
        var volume: Float = 0.8
        var halfTime = false
    }

    /// Состояние генератора, живёт только в аудиопотоке.
    private final class RenderState {
        var samplesToNextClick = 0
        var clickPosition = Int.max
    }

    private let params = OSAllocatedUnfairLock(initialState: Params())
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false

    var bpm: Double {
        get { params.withLock { $0.bpm } }
        set { params.withLock { $0.bpm = min(300, max(30, newValue)) } }
    }

    var volume: Float {
        get { params.withLock { $0.volume } }
        set { params.withLock { $0.volume = min(1, max(0, newValue)) } }
    }

    var halfTime: Bool {
        get { params.withLock { $0.halfTime } }
        set { params.withLock { $0.halfTime = newValue } }
    }

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

#if os(watchOS)
    /// На часах фоновый звук возможен только в режиме длительного воспроизведения,
    /// а он требует Bluetooth-наушников. Система сама покажет выбор наушников.
    func start() async throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        let activated = try await session.activate(options: [])
        guard activated else { throw MetronomeError.noHeadphones }
        try rebuildGraph()
        try engine.start()
        isRunning = true
    }
#else
    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        try rebuildGraph()
        try engine.start()
        isRunning = true
    }
#endif

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func rebuildGraph() throws {
        if let old = sourceNode {
            engine.detach(old)
            sourceNode = nil
        }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "Metronome", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "Не удалось создать аудиоформат")])
        }
        let click = Metronome.makeClick(sampleRate: sampleRate)
        let state = RenderState()
        let params = self.params

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let current = params.withLock { $0 }
            let clicksPerMinute = current.halfTime ? current.bpm / 2 : current.bpm
            let interval = max(1, Int((sampleRate * 60.0 / clicksPerMinute).rounded()))
            if state.samplesToNextClick > interval {
                state.samplesToNextClick = interval
            }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first,
                  let out = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            for index in 0..<frames {
                if state.samplesToNextClick <= 0 {
                    state.clickPosition = 0
                    state.samplesToNextClick = interval
                }
                var sample: Float = 0
                if state.clickPosition < click.count {
                    sample = click[state.clickPosition] * current.volume
                    state.clickPosition += 1
                }
                out[index] = sample
                state.samplesToNextClick -= 1
            }
            for extra in buffers.dropFirst() {
                if let dst = extra.mData?.assumingMemoryBound(to: Float.self) {
                    dst.update(from: out, count: frames)
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        engine.prepare()
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isRunning { engine.pause() }
        case .ended:
            guard isRunning else { return }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? engine.start()
            }
        @unknown default:
            break
        }
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        engine.stop()
        try? rebuildGraph()
        try? engine.start()
    }

    /// Короткий щелчок: две гармоники с быстрым затуханием, 30 мс.
    private static func makeClick(sampleRate: Double) -> [Float] {
        let duration = 0.03
        let count = Int(sampleRate * duration)
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let envelope = exp(-t * 120)
            let tone = sin(2 * .pi * 1500 * t) * 0.7 + sin(2 * .pi * 3000 * t) * 0.3
            return Float(envelope * tone)
        }
    }
}
