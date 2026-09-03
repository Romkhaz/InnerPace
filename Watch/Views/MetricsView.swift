import SwiftUI

/// Главный экран тренировки: ритм и фактический каденс, пульс с зоной,
/// контакт с землёй, вертикальные колебания и эффективность.
struct MetricsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                rhythmCard
                heartCard
                formCard
            }
            .padding(.horizontal, 2)
        }
    }

    private var rhythmCard: some View {
        VStack(spacing: -2) {
            Text("\(model.cadence)")
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.cadence)
            HStack(spacing: 4) {
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text("шаг")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(model.actualCadence.map(String.init) ?? "—")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                if model.warmupRemaining > 0 {
                    Text("· разминка \(formatElapsed(model.warmupRemaining))")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if model.phase == .paused {
                    Text("· пауза")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
                Text("\(model.settings.heartRateMax)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
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

    private var formCard: some View {
        HStack {
            metric(model.groundContactMs.map { "\(Int($0.rounded()))" } ?? "—", "мс контакт")
            Spacer()
            metric(model.verticalOscillationCm.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", "см колеб.")
            Spacer()
            metric(formatEfficiency(model.recentEfficiency), "м/удар")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
