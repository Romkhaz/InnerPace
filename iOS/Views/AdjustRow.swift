import SwiftUI

/// Ряд настройки числа: ползунок для быстрого перемещения по диапазону
/// и кнопки плюс-минус для точной доводки. Каждый шаг отзывается вибрацией.
struct AdjustRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                if let unit {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    set(value - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(value <= range.lowerBound)

                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { set(Int($0.rounded())) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )

                Button {
                    set(value + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.selection, trigger: value)
        .onChange(of: range) { _, new in
            set(min(new.upperBound, max(new.lowerBound, value)))
        }
    }

    private func set(_ raw: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        if clamped != value { value = clamped }
    }
}
