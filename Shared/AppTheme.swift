import Foundation

/// Оформление: авто следует за системой на телефоне, на часах равно светлой.
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }
}
