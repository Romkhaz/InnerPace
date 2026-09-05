import AVFoundation
import Foundation

/// Короткие голосовые подсказки через системный синтез речи. Язык берётся
/// из языка интерфейса.
final class VoiceCues {
    private let synthesizer = AVSpeechSynthesizer()

    var volume: Float = 1

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.volume = min(1, max(0, volume))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
    }

    private var languageCode: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code == "ru" ? "ru-RU" : "en-US"
    }
}

/// Решает, когда менять тембр щелчка и что говорить. Общий для телефона и часов.
final class CueCoordinator {
    let voice = VoiceCues()

    private var wasOverLimit = false
    private var lastCueAt: Date?

    func reset() {
        wasOverLimit = false
        lastCueAt = nil
    }

    /// Вызывается раз в секунду. Возвращает строку для журнала на переходах.
    func update(overLimit: Bool, settings: RegulatorSettings, now: Date) -> String? {
        voice.volume = Float(settings.voiceVolume)
        if overLimit != wasOverLimit {
            wasOverLimit = overLimit
            lastCueAt = now
            if settings.voiceCues {
                voice.say(overLimit ? String(localized: "Сбавь") : String(localized: "В норме"))
            }
            return overLimit ? String(localized: "Предел: сбавьте усилие") : String(localized: "Пульс в норме")
        }
        if overLimit, settings.voiceCues, settings.voiceRepeatSeconds > 0,
           let lastCueAt, now.timeIntervalSince(lastCueAt) >= TimeInterval(settings.voiceRepeatSeconds) {
            self.lastCueAt = now
            voice.say(String(localized: "Сбавь"))
        }
        return nil
    }
}
