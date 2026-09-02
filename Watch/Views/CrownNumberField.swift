import SwiftUI

/// Плитка с числом. Нажатие выбирает её, дальше значение меняется колёсиком
/// Digital Crown. Повторное нажатие снимает выделение.
struct CrownNumberField<Field: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let field: Field
    @FocusState.Binding var focused: Field?
    var unit: String = ""

    @State private var crownValue: Double = 0

    private var isFocused: Bool { focused == field }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isFocused ? Color.green : Color.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isFocused ? 0.16 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.green : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .focusable(true)
        .focused($focused, equals: field)
        .digitalCrownRotation(
            $crownValue,
            from: Double(range.lowerBound),
            through: Double(range.upperBound),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onTapGesture {
            // Повторное нажатие снимает выделение, и колёсико снова прокручивает экран.
            focused = isFocused ? nil : field
        }
        .onAppear {
            crownValue = Double(value)
        }
        .onChange(of: crownValue) { _, new in
            let rounded = Int(new.rounded())
            if rounded != value { setValue(rounded) }
        }
        .onChange(of: value) { _, new in
            if Int(crownValue.rounded()) != new { crownValue = Double(new) }
        }
        .onChange(of: range) { _, new in
            setValue(value)
            if !new.contains(Int(crownValue.rounded())) { crownValue = Double(value) }
        }
    }

    private func setValue(_ raw: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        if clamped != value { value = clamped }
    }
}
