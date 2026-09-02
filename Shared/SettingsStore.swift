import Foundation
import Observation

/// Хранит настройки в UserDefaults и отдаёт их интерфейсу.
@Observable
final class SettingsStore {
    var settings: RegulatorSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let key = "regulator.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(RegulatorSettings.self, from: data) {
            settings = stored.normalized()
        } else {
            settings = .default
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
