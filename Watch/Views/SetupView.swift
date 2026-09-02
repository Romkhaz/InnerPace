import SwiftUI

/// Экран перед стартом: границы пульса и каденса, кнопка «Старт».
struct SetupView: View {
    enum Field: Hashable {
        case heartRateMin, heartRateMax, cadenceMin, cadenceMax
    }

    @Environment(WatchRunModel.self) private var model
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var store = model.settingsStore
        let settings = store.settings
        ScrollView {
            VStack(spacing: 8) {
                if let summary = model.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    CrownNumberField(title: "Пульс от", value: $store.settings.heartRateMin,
                                     range: 60...(settings.heartRateMax - 1),
                                     field: .heartRateMin, focused: $focused)
                    CrownNumberField(title: "Пульс до", value: $store.settings.heartRateMax,
                                     range: (settings.heartRateMin + 1)...210,
                                     field: .heartRateMax, focused: $focused)
                }
                HStack(spacing: 6) {
                    CrownNumberField(title: "Каденс от", value: $store.settings.cadenceMin,
                                     range: 120...(settings.cadenceMax - 1),
                                     field: .cadenceMin, focused: $focused)
                    CrownNumberField(title: "Каденс до", value: $store.settings.cadenceMax,
                                     range: (settings.cadenceMin + 1)...220,
                                     field: .cadenceMax, focused: $focused)
                }
                Text("Нажмите на число и крутите колёсико. Ещё нажатие снимает выделение")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await model.start() }
                } label: {
                    Label("Старт", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if let error = model.errorText {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    Label("Ещё", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("InnerPace")
    }
}

/// Тонкие параметры регулятора и звука.
struct AdvancedSettingsView: View {
    enum Field: Hashable {
        case holdBand, interval, maxStep, smoothing
    }

    @Environment(WatchRunModel.self) private var model
    @FocusState private var focused: Field?
    @State private var interval: Int = 5
    @State private var smoothing: Int = 10

    var body: some View {
        @Bindable var store = model.settingsStore
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    CrownNumberField(title: "Удержание", value: $store.settings.holdBand,
                                     range: 0...15, field: .holdBand, focused: $focused)
                    CrownNumberField(title: "Интервал", value: $interval,
                                     range: 2...30, field: .interval, focused: $focused, unit: "с")
                }
                HStack(spacing: 6) {
                    CrownNumberField(title: "Шаг", value: $store.settings.maxStep,
                                     range: 1...10, field: .maxStep, focused: $focused)
                    CrownNumberField(title: "Сглажив.", value: $smoothing,
                                     range: 0...30, field: .smoothing, focused: $focused, unit: "с")
                }
                Toggle("Каждый второй шаг", isOn: $store.settings.halfTimeClick)
                    .font(.caption)
                Slider(value: $store.settings.clickVolume, in: 0...1) {
                    Text("Громкость")
                }
                Text("Громкость")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ещё")
        .onAppear {
            interval = Int(store.settings.adjustInterval)
            smoothing = Int(store.settings.smoothingSeconds)
        }
        .onChange(of: interval) { _, new in
            store.settings.adjustInterval = TimeInterval(new)
        }
        .onChange(of: smoothing) { _, new in
            store.settings.smoothingSeconds = Double(new)
        }
    }
}
