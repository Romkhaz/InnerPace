import SwiftUI

/// Отчёт о тренировке. Один и тот же на телефоне и часах.
struct ReportView: View {
    let summary: WorkoutSummary
    var onDone: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                row("Дистанция", formatDistance(summary.distanceMeters))
                row("Время", formatElapsed(summary.duration))
                row("Средний темп", formatPace(summary.averagePaceSecondsPerKm), unit: "мин/км")
            }
            Section {
                row("Средний пульс", summary.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                row("Средний каденс", summary.averageCadence.map { "\(Int($0.rounded()))" } ?? "—", unit: "шаг/мин")
                row("Средний ритм", summary.averageMetronome.map { "\(Int($0.rounded()))" } ?? "—", unit: "BPM")
            }
            Section {
                row("Эффективность", formatEfficiency(summary.efficiencyMetersPerBeat), unit: "м/удар")
                if let contact = summary.averageGroundContactMs {
                    row("Контакт с землёй", "\(Int(contact.rounded()))", unit: "мс")
                }
                if let oscillation = summary.averageVerticalOscillationCm {
                    row("Верт. колебания", oscillation.formatted(.number.precision(.fractionLength(1))), unit: "см")
                }
            }
            if let onDone {
                Section {
                    Button(action: onDone) {
                        Label("Готово", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .navigationTitle(Text(summary.date, format: .dateTime.day().month().hour().minute()))
    }

    private func row(_ title: LocalizedStringKey, _ value: String, unit: LocalizedStringKey? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Метров на удар с двумя знаками.
func formatEfficiency(_ value: Double?) -> String {
    guard let value, value.isFinite, value > 0 else { return "—" }
    return value.formatted(.number.precision(.fractionLength(2)))
}
