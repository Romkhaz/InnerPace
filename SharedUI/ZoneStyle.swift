import SwiftUI

/// Палитра в цветах иконки: оранжевый, персиковый, коралловый. Есть светлый
/// и тёмный вариант, экраны берут её из окружения.
struct Palette {
    let isDark: Bool

    // Базовые цвета иконки.
    let orange = Color(red: 0.97, green: 0.53, blue: 0.17)
    let coral = Color(red: 1.0, green: 0.24, blue: 0.36)
    let peach = Color(red: 1.0, green: 0.80, blue: 0.64)
    let deepCoral = Color(red: 0.91, green: 0.14, blue: 0.29)

    let background: Color
    let card: Color
    let cardBorder: Color
    let ink: Color
    let inkSecondary: Color
    let track: Color

    static let light = Palette(
        isDark: false,
        background: Color(red: 1.0, green: 0.97, blue: 0.94),
        card: .white,
        cardBorder: Color(red: 1.0, green: 0.85, blue: 0.75),
        ink: Color(red: 0.16, green: 0.10, blue: 0.08),
        inkSecondary: Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.55),
        track: Color(red: 0.16, green: 0.10, blue: 0.08).opacity(0.12)
    )

    static let dark = Palette(
        isDark: true,
        background: Color(red: 0.10, green: 0.08, blue: 0.07),
        card: Color(red: 0.16, green: 0.13, blue: 0.12),
        cardBorder: Color(red: 0.30, green: 0.22, blue: 0.18),
        ink: Color(red: 0.98, green: 0.94, blue: 0.91),
        inkSecondary: Color(red: 0.98, green: 0.94, blue: 0.91).opacity(0.6),
        track: Color.white.opacity(0.15)
    )

    private init(isDark: Bool, background: Color, card: Color, cardBorder: Color,
                 ink: Color, inkSecondary: Color, track: Color) {
        self.isDark = isDark
        self.background = background
        self.card = card
        self.cardBorder = cardBorder
        self.ink = ink
        self.inkSecondary = inkSecondary
        self.track = track
    }

    var cadenceGradient: LinearGradient {
        LinearGradient(colors: [orange, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var startColor: Color { orange }
    var stopColor: Color { deepCoral }

    /// Акцент зоны: маркер на шкале, сердце.
    func accent(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown: return inkSecondary
        case .below: return orange
        case .inside, .above: return .white
        }
    }

    /// Фон карточки зоны: ниже цели персиковая, в зоне оранжевая, выше коралловая.
    func gradient(_ zone: HeartRateZone) -> LinearGradient {
        let colors: [Color]
        switch zone {
        case .unknown:
            colors = isDark
                ? [Color(red: 0.18, green: 0.15, blue: 0.13), Color(red: 0.14, green: 0.11, blue: 0.10)]
                : [Color.white, Color(red: 0.98, green: 0.95, blue: 0.92)]
        case .below:
            colors = isDark
                ? [Color(red: 0.38, green: 0.24, blue: 0.15), Color(red: 0.28, green: 0.18, blue: 0.12)]
                : [Color(red: 1.0, green: 0.89, blue: 0.78), Color(red: 1.0, green: 0.82, blue: 0.66)]
        case .inside:
            colors = [Color(red: 1.0, green: 0.60, blue: 0.27), Color(red: 1.0, green: 0.46, blue: 0.20)]
        case .above:
            colors = [Color(red: 1.0, green: 0.36, blue: 0.45), Color(red: 0.90, green: 0.13, blue: 0.29)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Цвет текста на карточке зоны.
    func foreground(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return ink
        case .inside, .above: return .white
        }
    }

    func foregroundSecondary(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return inkSecondary
        case .inside, .above: return Color.white.opacity(0.8)
        }
    }

    /// Дорожка шкалы зоны на карточке.
    func trackColor(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown, .below: return track
        case .inside, .above: return Color.white.opacity(0.3)
        }
    }

    /// Какую палитру выбрать по настройке и системной теме.
    static func resolve(theme: AppTheme, systemIsDark: Bool) -> Palette {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemIsDark ? .dark : .light
        }
    }
}

enum ZoneStyle {
    static func index(_ zone: HeartRateZone) -> Int {
        switch zone {
        case .unknown: return 0
        case .below: return 1
        case .inside: return 2
        case .above: return 3
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Карточка с тонкой рамкой в цветах палитры.
struct PaletteCard: ViewModifier {
    @Environment(\.palette) private var palette
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(palette.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(palette.cardBorder, lineWidth: 1))
            .shadow(color: palette.orange.opacity(palette.isDark ? 0 : 0.10), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func lightCard(radius: CGFloat = 22) -> some View {
        modifier(PaletteCard(radius: radius))
    }
}
