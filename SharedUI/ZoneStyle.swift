import SwiftUI

/// Цвета зон пульса и карточки каденса, общие для телефона и часов.
enum ZoneStyle {
    static let cadenceGradient = LinearGradient(
        colors: [Color(red: 0.07, green: 0.42, blue: 0.48), Color(red: 0.10, green: 0.33, blue: 0.72)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let startBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let stopRed = Color(red: 0.93, green: 0.23, blue: 0.27)

    static func index(_ zone: HeartRateZone) -> Int {
        switch zone {
        case .unknown: return 0
        case .below: return 1
        case .inside: return 2
        case .above: return 3
        }
    }

    static func accent(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown: return Color.white.opacity(0.6)
        case .below: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .inside: return Color(red: 0.35, green: 0.85, blue: 0.45)
        case .above: return Color(red: 1.0, green: 0.3, blue: 0.3)
        }
    }

    static func gradient(_ zone: HeartRateZone) -> LinearGradient {
        let colors: [Color]
        switch zone {
        case .unknown:
            colors = [Color(white: 0.18), Color(white: 0.12)]
        case .below:
            colors = [Color(red: 0.10, green: 0.28, blue: 0.55), Color(red: 0.06, green: 0.16, blue: 0.36)]
        case .inside:
            colors = [Color(red: 0.08, green: 0.42, blue: 0.22), Color(red: 0.04, green: 0.26, blue: 0.16)]
        case .above:
            colors = [Color(red: 0.55, green: 0.12, blue: 0.16), Color(red: 0.32, green: 0.07, blue: 0.12)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
