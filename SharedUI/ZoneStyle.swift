import SwiftUI

/// Светлая палитра в цветах иконки: оранжевый, персиковый, коралловый.
/// Общая для телефона и часов.
enum ZoneStyle {
    // Базовые цвета иконки.
    static let orange = Color(red: 0.97, green: 0.53, blue: 0.17)
    static let coral = Color(red: 1.0, green: 0.24, blue: 0.36)
    static let peach = Color(red: 1.0, green: 0.80, blue: 0.64)
    static let deepCoral = Color(red: 0.91, green: 0.14, blue: 0.29)

    /// Фон экрана и карточек.
    static let background = Color(red: 1.0, green: 0.97, blue: 0.94)
    static let card = Color.white
    static let cardBorder = Color(red: 1.0, green: 0.85, blue: 0.75)
    /// Основной и второстепенный текст на светлых карточках.
    static let ink = Color(red: 0.16, green: 0.10, blue: 0.08)
    static let inkSecondary = Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.55)
    /// Дорожка шкалы на светлой карточке.
    static let track = Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.12)

    static let cadenceGradient = LinearGradient(
        colors: [orange, coral],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let startColor = orange
    static let stopColor = deepCoral
    /// Прежние имена, чтобы не трогать вызовы.
    static let startBlue = orange
    static let stopRed = deepCoral

    static func index(_ zone: HeartRateZone) -> Int {
        switch zone {
        case .unknown: return 0
        case .below: return 1
        case .inside: return 2
        case .above: return 3
        }
    }

    /// Акцент зоны: маркер на шкале, сердце.
    static func accent(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown: return Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.35)
        case .below: return orange
        case .inside: return Color.white
        case .above: return Color.white
        }
    }

    /// Фон карточки зоны: ниже цели персиковая, в зоне оранжевая, выше коралловая.
    static func gradient(_ zone: HeartRateZone) -> LinearGradient {
        let colors: [Color]
        switch zone {
        case .unknown:
            colors = [Color.white, Color(red: 0.98, green: 0.95, blue: 0.92)]
        case .below:
            colors = [Color(red: 1.0, green: 0.89, blue: 0.78), Color(red: 1.0, green: 0.82, blue: 0.66)]
        case .inside:
            colors = [Color(red: 1.0, green: 0.60, blue: 0.27), Color(red: 1.0, green: 0.46, blue: 0.20)]
        case .above:
            colors = [Color(red: 1.0, green: 0.36, blue: 0.45), Color(red: 0.90, green: 0.13, blue: 0.29)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Цвет текста на карточке зоны.
    static func foreground(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return ink
        case .inside, .above: return .white
        }
    }

    static func foregroundSecondary(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return inkSecondary
        case .inside, .above: return Color.white.opacity(0.8)
        }
    }

    /// Дорожка шкалы зоны на карточке.
    static func trackColor(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return track
        case .inside, .above: return Color.white.opacity(0.3)
        }
    }
}

/// Светлая карточка с тонкой персиковой рамкой.
struct LightCard: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(ZoneStyle.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(ZoneStyle.cardBorder, lineWidth: 1))
            .shadow(color: ZoneStyle.orange.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func lightCard(radius: CGFloat = 22) -> some View {
        modifier(LightCard(radius: radius))
    }
}
