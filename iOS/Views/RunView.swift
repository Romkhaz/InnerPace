import SwiftUI

struct RunView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        List {
            Section {
                sensorRow
            }
            Section {
                dashboard
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
            Section {
                controls
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                if let error = session.lastError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("Журнал") {
                if session.events.isEmpty {
                    Text("Пока пусто").foregroundStyle(.secondary)
                }
                ForEach(session.events) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.time, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(event.text)
                    }
                }
            }
        }
    }

    private var sensorRow: some View {
        HStack {
            Circle()
                .fill(session.polar.state.isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(session.polar.state.label)
                if let battery = session.polar.batteryLevel, session.polar.state.isConnected {
                    (Text("Батарея") + Text(verbatim: " \(battery)%")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if session.polar.state.isConnected {
                Button("Отключить") { session.polar.disconnect() }
                    .buttonStyle(.bordered)
            } else {
                Button("Подключить") { session.polar.connect() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var dashboard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(session.cadence)")
                    .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                Text("шагов в минуту")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                VStack {
                    Text(session.heartRate.map(String.init) ?? "—")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color(for: session.rawZone))
                    Text("пульс · \(session.heartRateSource.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack {
                    Text(session.smoothedHeartRate.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color(for: session.zone))
                    Text("сглаженный")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ZoneBar(heartRate: session.smoothedHeartRate ?? session.heartRate.map(Double.init),
                    settings: session.settings)
            Text(formatElapsed(session.elapsed))
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                session.toggleStartPause()
            } label: {
                Label(startTitle, systemImage: startIcon)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                session.stop()
            } label: {
                Label("Стоп", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .disabled(session.state == .idle)
        }
    }

    private var startTitle: LocalizedStringKey {
        switch session.state {
        case .idle: return "Старт"
        case .running: return "Пауза"
        case .paused: return "Дальше"
        }
    }

    private var startIcon: String {
        session.state == .running ? "pause.fill" : "play.fill"
    }

    private func color(for zone: HeartRateZone) -> Color {
        switch zone {
        case .unknown: return .primary
        case .below: return .blue
        case .inside: return .green
        case .above: return .red
        }
    }
}

/// Полоса зоны пульса с маркером текущего значения.
struct ZoneBar: View {
    let heartRate: Double?
    let settings: RegulatorSettings

    private var lower: Double { Double(settings.heartRateMin) - 20 }
    private var upper: Double { Double(settings.heartRateMax) + 20 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: width * fraction(Double(settings.heartRateMax)) - width * fraction(Double(settings.heartRateMin)))
                    .offset(x: width * fraction(Double(settings.heartRateMin)))
                if let heartRate {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 14, height: 14)
                        .offset(x: width * fraction(heartRate) - 7)
                }
            }
        }
        .frame(height: 14)
        .overlay(alignment: .bottom) {
            HStack {
                Text("\(settings.heartRateMin)")
                Spacer()
                Text("\(settings.heartRateMax)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .offset(y: 18)
        }
        .padding(.bottom, 16)
    }

    private func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - lower) / (upper - lower)))
    }
}
