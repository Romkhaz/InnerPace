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
            ZoneStyle.cadenceGradient,
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    // MARK: - Пульс

    private func heartCard(value: String, caption: Text, zone: HeartRateZone) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(ZoneStyle.accent(zone))
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
        .background(ZoneStyle.gradient(zone), in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(zone))
    }

    // MARK: - Зона и время

    private var zoneCard: some View {
        VStack(spacing: 6) {
            ZoneBar(
                heartRate: session.smoothedHeartRate ?? session.heartRate.map(Double.init),
                settings: session.settings,
                accent: ZoneStyle.accent(session.zone)
            )
            Text(formatElapsed(session.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(ZoneStyle.gradient(session.zone), in: RoundedRectangle(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(session.zone))
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 44) {
            RoundButton(
                icon: session.state == .running ? "pause.fill" : "play.fill",
                title: startTitle,
                color: ZoneStyle.startBlue,
                enabled: true
            ) {
                session.toggleStartPause()
            }
            RoundButton(
                icon: "stop.fill",
                title: "Стоп",
                color: ZoneStyle.stopRed,
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
