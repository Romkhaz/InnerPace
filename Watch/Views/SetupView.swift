import SwiftUI

/// Экран перед стартом: две главные настройки и кнопка «Старт».
struct SetupView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let last = model.store.workouts.first {
                    NavigationLink {
                        ReportView(summary: last)
                    } label: {
                        HStack {
                            Text("Последняя")
                            Spacer()
                            Text("\(formatDistance(last.distanceMeters)) · \(formatElapsed(last.duration))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                QuickSettingsView()
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

/// Две главные плитки: нижняя граница ритма и целевой пульс.
/// Верхняя граница ритма и нижняя граница пульса считаются автоматически.
struct QuickSettingsView: View {
    enum Field: Hashable {
        case cadenceMin, heartRateMax
    }

    @Environment(WatchRunModel.self) private var model
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var store = model.settingsStore
        let cadenceMin = Binding<Int>(
            get: { store.settings.cadenceMin },
            set: { store.settings.setCadenceMinDerivingMax($0) }
        )
        let heartRateMax = Binding<Int>(
            get: { store.settings.heartRateMax },
            set: { store.settings.setTargetHeartRateKeepingZoneWidth($0) }
        )
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                CrownNumberField(title: "Ритм от", value: cadenceMin,
                                 range: 120...220, field: .cadenceMin, focused: $focused)
                CrownNumberField(title: "Пульс до", value: heartRateMax,
                                 range: 80...210, field: .heartRateMax, focused: $focused)
            }
            Text("Ритм до \(store.settings.cadenceMax) · пульс от \(store.settings.heartRateMin)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Тонкие параметры регулятора, звук и режим разработчика.
struct AdvancedSettingsView: View {
    enum Field: Hashable {
        case cadenceMax, span, heartRateMin, approach, holdBand, warmup, slowdown, smoothing, interval, maxStep
    }

    @Environment(WatchRunModel.self) private var model
    @FocusState private var focused: Field?
    @State private var interval: Int = 5
    @State private var smoothing: Int = 5
    @State private var slowdown: Int = 3

    var body: some View {
        @Bindable var store = model.settingsStore
        let settings = store.settings
        ScrollView {
            VStack(spacing: 6) {
                sectionTitle("Ритм")
                HStack(spacing: 6) {
                    CrownNumberField(title: "Ритм до", value: $store.settings.cadenceMax,
                                     range: (settings.cadenceMin + 1)...240, field: .cadenceMax, focused: $focused)
                    CrownNumberField(title: "Запас", value: $store.settings.cadenceSpanPercent,
                                     range: 1...50, field: .span, focused: $focused, unit: "%")
                }
                sectionTitle("Пульс")
                HStack(spacing: 6) {
                    CrownNumberField(title: "Пульс от", value: $store.settings.heartRateMin,
                                     range: 40...(settings.heartRateMax - 1), field: .heartRateMin, focused: $focused)
                    CrownNumberField(title: "Подход", value: $store.settings.approachPercent,
                                     range: 0...30, field: .approach, focused: $focused, unit: "%")
                }
                HStack(spacing: 6) {
                    CrownNumberField(title: "Удержание", value: $store.settings.holdBand,
                                     range: 0...20, field: .holdBand, focused: $focused)
                    CrownNumberField(title: "Разминка", value: $store.settings.warmupMinutes,
                                     range: 0...15, field: .warmup, focused: $focused, unit: "мин")
                }
                sectionTitle("Звук")
                Toggle("Каждый второй шаг", isOn: $store.settings.halfTimeClick)
                    .font(.caption)
                Slider(value: $store.settings.clickVolume, in: 0...1) {
                    Text("Громкость")
                }
                Text("Громкость")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                sectionTitle("Разработчик")
                Toggle("Телеметрия в файл", isOn: $store.settings.developerMode)
                    .font(.caption)
                HStack(spacing: 6) {
                    CrownNumberField(title: "Спуск", value: $slowdown,
                                     range: 1...10, field: .slowdown, focused: $focused, unit: "×")
                    CrownNumberField(title: "Сглажив.", value: $smoothing,
                                     range: 0...30, field: .smoothing, focused: $focused, unit: "с")
                }
                HStack(spacing: 6) {
                    CrownNumberField(title: "Интервал", value: $interval,
                                     range: 2...30, field: .interval, focused: $focused, unit: "с")
                    CrownNumberField(title: "Шаг", value: $store.settings.maxStep,
                                     range: 1...10, field: .maxStep, focused: $focused)
                }
                Text("Телеметрия пишется посекундно в CSV и пересылается на телефон, папка InnerPace в «Файлах».")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ещё")
        .onAppear {
            interval = Int(store.settings.adjustInterval)
            smoothing = Int(store.settings.smoothingSeconds)
            slowdown = Int(store.settings.slowdownFactor.rounded())
        }
        .onChange(of: interval) { _, new in store.settings.adjustInterval = TimeInterval(new) }
        .onChange(of: smoothing) { _, new in store.settings.smoothingSeconds = Double(new) }
        .onChange(of: slowdown) { _, new in store.settings.slowdownFactor = Double(new) }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
