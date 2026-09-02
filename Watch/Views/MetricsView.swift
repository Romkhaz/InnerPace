import SwiftUI

/// Главный экран тренировки: каденс, пульс, темп, дистанция, время.
struct MetricsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatElapsed(model.elapsed))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.yellow)
                if model.phase == .paused {
                    Text("пауза")
                        .font(.footnote)
                        .foregroundStyle(.yellow)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(model.cadence)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                Text("шаг/мин")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(zoneColor)
                Text(model.heartRate.map(String.init) ?? "—")
                    .font(.title3.monospacedDigit())
                if let smoothed = model.smoothedHeartRate {
                    Text("· \(Int(smoothed.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatPace(model.paceSecondsPerKm))
                    .font(.title3.monospacedDigit())
                Text("мин/км")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(formatDistance(model.distanceMeters))
                .font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var zoneColor: Color {
        switch model.zone {
        case .unknown: return .secondary
        case .below: return .blue
        case .inside: return .green
        case .above: return .red
        }
    }
}
