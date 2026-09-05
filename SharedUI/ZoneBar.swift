import SwiftUI

/// Шкала зоны пульса: зона подсвечена, бегун отмечает текущий пульс.
struct ZoneBar: View {
    let heartRate: Double?
    let settings: RegulatorSettings
    var accent: Color = ZoneStyle.orange
    var track: Color = ZoneStyle.track
    var labelColor: Color = ZoneStyle.inkSecondary
    var barHeight: CGFloat = 10
    var markerSize: CGFloat = 30
    var showsLabels = true

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
                        .fill(track)
                        .frame(height: barHeight)
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(width: max(0, zoneEnd - zoneStart), height: barHeight)
                        .offset(x: zoneStart)
                    if let heartRate {
                        Image(systemName: "figure.run")
                            .font(.system(size: markerSize / 2, weight: .bold))
                            .foregroundStyle(ZoneStyle.ink)
                            .frame(width: markerSize, height: markerSize)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().stroke(accent, lineWidth: 2))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .offset(x: width * fraction(heartRate) - markerSize / 2)
                            .animation(.easeInOut(duration: 0.6), value: heartRate)
                    }
                }
                .frame(height: markerSize)
            }
            .frame(height: markerSize)
            if showsLabels {
                HStack {
                    Text("\(settings.heartRateMin)")
                    Spacer()
                    Text("\(settings.heartRateMax)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(labelColor)
            }
        }
    }

    private func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - lower) / (upper - lower)))
    }
}
