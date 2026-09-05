import SwiftUI

/// Главный экран тренировки: ритм и фактический каденс в одну строку,
/// пульс с зоной, ниже крупно эффективность, контакт с землёй и колебания.
struct MetricsView: View {
    @Environment(\.palette) private var palette
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
        .background(palette.background.ignoresSafeArea())
    }

    private var rhythmCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                bigNumber("\(model.cadence)", "BPM")
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: 30)
                bigNumber(model.actualCadence.map(String.init) ?? "—", "SPM")
            }
            if model.phase == .paused {
                Text("пауза")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(palette.cadenceGradient, in: RoundedRectangle(cornerRadius: 14))
    }

    private func bigNumber(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: -4) {
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private var heartCard: some View {
        let zone = model.zone
        return VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.accent(zone))
                Text(model.heartRate.map(String.init) ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.foreground(zone))
                if let smoothed = model.smoothedHeartRate {
                    Text("· \(Int(smoothed.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(palette.foregroundSecondary(zone))
                }
                Spacer()
                Text("\(model.settings.heartRateMax)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.foregroundSecondary(zone))
            }
            ZoneBar(
                heartRate: model.smoothedHeartRate ?? model.heartRate.map(Double.init),
                settings: model.settings,
                accent: palette.accent(zone),
                track: palette.trackColor(zone),
                barHeight: 5,
                markerSize: 14,
                showsLabels: false
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.gradient(zone), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.cardBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.4), value: ZoneStyle.index(zone))
    }

    private var formCard: some View {
        HStack(spacing: 4) {
            metric(formatEfficiency(model.recentEfficiency), "м/удар")
            metric(model.groundContactMs.map { "\(Int($0.rounded()))" } ?? "—", "мс контакт")
            metric(model.verticalOscillationCm.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", "см колеб.")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .lightCard(radius: 14)
    }

    private func metric(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: -2) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
