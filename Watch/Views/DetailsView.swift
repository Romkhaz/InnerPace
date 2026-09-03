import SwiftUI

/// Вторая страница: темп, средний темп, дистанция, время.
struct DetailsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                tile(formatElapsed(model.elapsed), "время", accent: .yellow)
                HStack(spacing: 4) {
                    tile(formatPace(model.paceSecondsPerKm), "темп, мин/км")
                    tile(formatPace(model.averagePaceSecondsPerKm), "средний темп")
                }
                tile(formatDistance(model.distanceMeters), "дистанция")
            }
            .padding(.horizontal, 2)
        }
    }

    private func tile(_ value: String, _ caption: LocalizedStringKey, accent: Color = .white) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
