import Foundation
import Observation

/// Хранит настройки в UserDefaults и отдаёт их интерфейсу.
@Observable
final class SettingsStore {
    var settings: RegulatorSettings {
        didSet { save() }
    }

    /// Снимок настроек перед последним применением рекомендации. Пока он есть,
    /// в настройках доступен возврат к нему.
    private(set) var previousSettings: RegulatorSettings?
    private(set) var previousSavedAt: Date?

    private let defaults: UserDefaults
    private let key = "regulator.settings"
    private let previousKey = "regulator.settings.previous"

    private struct Snapshot: Codable {
        var settings: RegulatorSettings
        var savedAt: Date
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(RegulatorSettings.self, from: data) {
            settings = stored.normalized()
        } else {
            settings = .default
        }
        if let data = defaults.data(forKey: previousKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            previousSettings = snapshot.settings.normalized()
            previousSavedAt = snapshot.savedAt
        }
    }

    /// Применяет рекомендацию, сохранив прежние настройки для возврата.
    /// Несколько применений подряд из одного отчёта хранят самый первый снимок.
    func applyRecommendation(at now: Date = Date(), _ change: (inout RegulatorSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        if previousSettings == nil {
            previousSettings = settings
            previousSavedAt = now
            savePrevious()
        }
        settings = next.normalized()
    }

    /// Возвращает настройки к снимку и забывает его.
    func revertToPrevious() {
        guard let previousSettings else { return }
        settings = previousSettings
        self.previousSettings = nil
        previousSavedAt = nil
        savePrevious()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    private func savePrevious() {
        if let previousSettings, let previousSavedAt,
           let data = try? JSONEncoder().encode(Snapshot(settings: previousSettings, savedAt: previousSavedAt)) {
            defaults.set(data, forKey: previousKey)
        } else {
            defaults.removeObject(forKey: previousKey)
        }
    }
}
