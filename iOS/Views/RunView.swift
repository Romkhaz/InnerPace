import SwiftUI

struct RunView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                sensorRow
                cadenceCard
                HStack(spacing: 12) {
                    heartCard(
                        value: session.heartRate.map(String.init) ?? "—",
                        caption: Text("пульс · \(session.heartRateSource.rawValue)"),
                        zone: session.rawZone
                    )
                    heartCard(
                        value: session.smoothedHeartRate.map { String(Int($0.rounded())) } ?? "—",
                        caption: Text("сглаженный"),
                        zone: session.zone
                    )
                }
                zoneCard
                controls
                if let error = session.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                historyRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Датчик

    private var sensorRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.polar.state.isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.polar.state.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let battery = session.polar.batteryLevel, session.polar.state.isConnected {
                    (Text("Батарея") + Text(verbatim: " \(battery)%"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if session.polar.state.isConnected {
                Button("Отключить") { session.polar.disconnect() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            } else {
                Button("Подключить") { session.polar.connect() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Каденс

    private var cadenceCard: some View {
        VStack(spacing: 2) {
            Text("\(session.cadence)")
                .font(.system(size: 92, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: session.cadence)
            Text("шагов в минуту")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.42, blue: 0.48), Color(red: 0.10, green: 0.33, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    // MARK: - Пульс

    private func heartCard(value: String, caption: Text, zone: HeartRateZone) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(zoneAccent(zone))
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            caption
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(zoneGradient(zone), in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.4), value: zoneIndex(zone))
    }

    // MARK: - Зона и время

    private var zoneCard: some View {
        VStack(spacing: 6) {
            ZoneBar(
                heartRate: session.smoothedHeartRate ?? session.heartRate.map(Double.init),
                settings: session.settings,
                accent: zoneAccent(session.zone)
            )
            Text(formatElapsed(session.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(zoneGradient(session.zone), in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.4), value: zoneIndex(session.zone))
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 44) {
            RoundButton(
                icon: session.state == .running ? "pause.fill" : "play.fill",
                title: startTitle,
                color: Color(red: 0.0, green: 0.48, blue: 1.0),
                enabled: true
            ) {
                session.toggleStartPause()
            }
            RoundButton(
                icon: "stop.fill",
                title: "Стоп",
                color: Color(red: 0.93, green: 0.23, blue: 0.27),
                enabled: session.state != .idle
            ) {
                session.stop()
            }
        }
        .padding(.vertical, 2)
    }

    private var startTitle: LocalizedStringKey {
        switch session.state {
        case .idle: return "Старт"
        case .running: return "Пауза"
        case .paused: return "Дальше"
        }
    }

    // MARK: - История

    private var historyRow: some View {
        NavigationLink {
            HistoryView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("История")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(session.events.first?.text ?? String(localized: "Пока пусто"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Цвета зон

    private func zoneIndex(_ zone: HeartRateZone) -> Int {
        switch zone {
        case .unknown: return 0
        case .below: return 1
        case .inside: return 2
        case .above: return 3
        }
    }

    private func zoneAccent(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown: return Color.white.opacity(0.6)
        case .below: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .inside: return Color(red: 0.35, green: 0.85, blue: 0.45)
        case .above: return Color(red: 1.0, green: 0.3, blue: 0.3)
        }
    }

    private func zoneGradient(_ zone: HeartRateZone) -> LinearGradient {
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

/// Круглая кнопка с подписью под ней.
private struct RoundButton: View {
    let icon: String
    let title: LocalizedStringKey
    let color: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(enabled ? color : Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Шкала зоны пульса: зона подсвечена, бегун отмечает текущий пульс.
struct ZoneBar: View {
    let heartRate: Double?
    let settings: RegulatorSettings
    var accent: Color = .green

    private var lower: Double { Double(settings.heartRateMin) - 20 }
    private var upper: Double { Double(settings.heartRateMax) + 20 }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let zoneStart = width * fraction(Double(settings.heartRateMin))
                let zoneEnd = width * fraction(Double(settings.heartRateMax))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 10)
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(width: max(0, zoneEnd - zoneStart), height: 10)
                        .offset(x: zoneStart)
                    if let heartRate {
                        Image(systemName: "figure.run")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(accent, in: Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                            .offset(x: width * fraction(heartRate) - 15)
                            .animation(.easeInOut(duration: 0.6), value: heartRate)
                    }
                }
                .frame(height: 30)
            }
            .frame(height: 30)
            HStack {
                Text("\(settings.heartRateMin)")
                Spacer()
                Text("\(settings.heartRateMax)")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - lower) / (upper - lower)))
    }
}
