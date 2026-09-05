import SwiftUI

/// Вторая страница: темп, средний темп, дистанция, время.
struct DetailsView: View {
    @Environment(\.palette) private var palette
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                tile(formatElapsed(model.elapsed), "время", accent: palette.coral)
                HStack(spacing: 4) {
                    tile(formatPace(model.paceSecondsPerKm), "темп")
                    tile(formatPace(model.averagePaceSecondsPerKm), "ср. темп")
                }
                tile(formatDistance(model.distanceMeters), "дистанция")
            }
            .padding(.horizontal, 2)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private func tile(_ value: String, _ caption: LocalizedStringKey, accent: Color? = nil) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent ?? palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .lightCard(radius: 14)
    }
}
