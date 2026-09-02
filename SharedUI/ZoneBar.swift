import SwiftUI

/// Шкала зоны пульса: зона подсвечена, бегун отмечает текущий пульс.
struct ZoneBar: View {
    let heartRate: Double?
    let settings: RegulatorSettings
    var accent: Color = .green
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
                        .fill(Color.white.opacity(0.15))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(width: max(0, zoneEnd - zoneStart), height: barHeight)
                        .offset(x: zoneStart)
                    if let heartRate {
                        Image(systemName: "figure.run")
                            .font(.system(size: markerSize / 2, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: markerSize, height: markerSize)
                            .background(accent, in: Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
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
                .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - lower) / (upper - lower)))
    }
}
