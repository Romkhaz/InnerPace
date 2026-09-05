import SwiftUI

struct RunView: View {
    @Environment(\.palette) private var palette
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
                        .foregroundStyle(palette.deepCoral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                historyRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(palette.background.ignoresSafeArea())
        .sheet(item: Binding(
            get: { session.report },
            set: { session.report = $0 }
        )) { summary in
            NavigationStack {
                ReportView(summary: summary) {
                    session.report = nil
                }
            }
        }
    }

    // MARK: - Датчик

    private var sensorRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.polar.state.isConnected ? palette.orange : palette.track)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.polar.state.label)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let battery = session.polar.batteryLevel, session.polar.state.isConnected {
                    (Text("Батарея") + Text(verbatim: " \(battery)%"))
                        .font(.caption)
                        .foregroundStyle(palette.inkSecondary)
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
        .lightCard()
    }

    // MARK: - Ритм

    private var cadenceCard: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                bigNumber("\(session.cadence)", "BPM")
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: 60)
                bigNumber(session.actualCadence.map(String.init) ?? "—", "SPM")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(palette.cadenceGradient, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: palette.coral.opacity(0.25), radius: 14, x: 0, y: 6)
    }

    private func bigNumber(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: -4) {
            Text(value)
                .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Пульс

    private func heartCard(value: String, caption: Text, zone: HeartRateZone) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(palette.accent(zone))
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.foreground(zone))
                .contentTransition(.numericText())
            caption
                .font(.subheadline)
                .foregroundStyle(palette.foregroundSecondary(zone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(palette.gradient(zone), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(palette.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(zone))
    }

    // MARK: - Зона и метрики

    private var zoneCard: some View {
        let zone = session.zone
        return VStack(spacing: 6) {
            ZoneBar(
                heartRate: session.smoothedHeartRate ?? session.heartRate.map(Double.init),
                settings: session.settings,
                accent: palette.accent(zone),
                track: palette.trackColor(zone),
                labelColor: palette.foregroundSecondary(zone)
            )
            HStack {
                metric(formatEfficiency(session.recentEfficiency), "м/удар", zone: zone)
                Spacer()
                metric(formatDistance(session.distanceMeters), "дистанция", zone: zone)
                Spacer()
                metric(formatPace(session.paceSecondsPerKm), "мин/км", zone: zone)
                Spacer()
                metric(formatElapsed(session.elapsed), "время", zone: zone)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(palette.gradient(zone), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(palette.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(zone))
    }

    private func metric(_ value: String, _ caption: LocalizedStringKey, zone: HeartRateZone) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.foreground(zone))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(palette.foregroundSecondary(zone))
        }
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 44) {
            RoundButton(
                icon: session.state == .running ? "pause.fill" : "play.fill",
                title: startTitle,
                color: palette.startColor,
                enabled: true
            ) {
                session.toggleStartPause()
            }
            RoundButton(
                icon: "stop.fill",
                title: "Стоп",
                color: palette.stopColor,
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
                        .foregroundStyle(palette.ink)
                    Text(session.events.first?.text ?? String(localized: "Пока пусто"))
                        .font(.footnote)
                        .foregroundStyle(palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.orange)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .lightCard()
        }
        .buttonStyle(.plain)
    }
}

/// Круглая кнопка с подписью под ней.
private struct RoundButton: View {
    @Environment(\.palette) private var palette
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
                    .background(enabled ? color : palette.track, in: Circle())
                    .shadow(color: enabled ? color.opacity(0.35) : .clear, radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            Text(title)
                .font(.footnote)
                .foregroundStyle(palette.inkSecondary)
        }
    }
}
