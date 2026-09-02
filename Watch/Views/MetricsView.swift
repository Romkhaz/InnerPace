import SwiftUI

/// Главный экран тренировки: каденс, пульс с зоной, темп, дистанция, время.
struct MetricsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(formatElapsed(model.elapsed))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.yellow)
                    if model.phase == .paused {
                        Text("пауза")
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                cadenceCard
                heartCard
                paceCard
            }
            .padding(.horizontal, 2)
        }
    }

    private var cadenceCard: some View {
        VStack(spacing: -2) {
            Text("\(model.cadence)")
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.cadence)
            Text("шаг/мин")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(ZoneStyle.cadenceGradient, in: RoundedRectangle(cornerRadius: 14))
    }

    private var heartCard: some View {
        let zone = model.zone
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(ZoneStyle.accent(zone))
                Text(model.heartRate.map(String.init) ?? "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                if let smoothed = model.smoothedHeartRate {
                    Text("· \(Int(smoothed.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            ZoneBar(
                heartRate: model.smoothedHeartRate ?? model.heartRate.map(Double.init),
                settings: model.settings,
                accent: ZoneStyle.accent(zone),
                barHeight: 5,
                markerSize: 16,
                showsLabels: false
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ZoneStyle.gradient(zone), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(zone))
    }

    private var paceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(formatPace(model.paceSecondsPerKm))
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                Text("мин/км")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatDistance(model.distanceMeters))
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                Text("дистанция")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
