import SwiftUI

/// Экран перед стартом: две главные настройки и кнопка «Старт».
struct SetupView: View {
    @Environment(\.palette) private var palette
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let last = model.store.workouts.first {
                    NavigationLink {
                        ReportView(summary: last, settingsStore: model.settingsStore, history: model.store.workouts)
                    } label: {
                        HStack {
                            Text("Последняя")
                            Spacer()
                            Text("\(formatDistance(last.distanceMeters)) · \(formatElapsed(last.duration))")
                                .foregroundStyle(palette.inkSecondary)
                        }
                        .font(.caption2)
                        .foregroundStyle(palette.ink)
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
                .tint(palette.orange)

                if let error = model.errorText {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(palette.deepCoral)
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
        .background(palette.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

/// Две главные плитки: нижняя граница ритма и целевой пульс.
/// Верхняя граница ритма и нижняя граница пульса считаются автоматически.
struct QuickSettingsView: View {
    @Environment(\.palette) private var palette
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
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let warning = RecommendationText.targetWarning(store.settings) {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(palette.deepCoral)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Тонкие параметры регулятора, звук и режим разработчика.
struct AdvancedSettingsView: View {
    @Environment(\.palette) private var palette
    enum Field: Hashable {
        case cadenceMax, span, heartRateMin, approach, holdBand, slowdown, smoothing, interval, maxStep, voiceRepeat, arm, ascent, predict, age, resting, warmup, floor
    }

    @Environment(WatchRunModel.self) private var model
    @FocusState private var focused: Field?
    @State private var interval: Int = 5
    @State private var smoothing: Int = 5
    @State private var slowdown: Int = 3
    @State private var ascentPercent: Int = 50
    @State private var warmupMinutes: Int = 8

    var body: some View {
        @Bindable var store = model.settingsStore
        ScrollView {
            VStack(spacing: 6) {
                revertBlock
                cadenceSection
                pulseSection
                zonesSection
                appearanceSection
                soundSection
                voiceSection
                developerSection
            }
            .padding(.horizontal, 4)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Ещё")
        .containerBackground(palette.background.gradient, for: .navigation)
        .onAppear(perform: loadLocals)
        .onChange(of: warmupMinutes) { _, new in setWarmup(new) }
        .onChange(of: ascentPercent) { _, new in setAscent(new) }
        .onChange(of: interval) { _, new in setInterval(new) }
        .onChange(of: smoothing) { _, new in setSmoothing(new) }
        .onChange(of: slowdown) { _, new in setSlowdown(new) }
    }

    private func loadLocals() {
        let s = model.settingsStore.settings
        interval = Int(s.adjustInterval)
        smoothing = Int(s.smoothingSeconds)
        slowdown = Int(s.slowdownFactor.rounded())
        ascentPercent = Int((s.ascentFactor * 100).rounded())
        warmupMinutes = s.warmupSeconds / 60
    }

    private func setWarmup(_ minutes: Int) { model.settingsStore.settings.warmupSeconds = minutes * 60 }
    private func setAscent(_ percent: Int) { model.settingsStore.settings.ascentFactor = Double(percent) / 100 }
    private func setInterval(_ seconds: Int) { model.settingsStore.settings.adjustInterval = TimeInterval(seconds) }
    private func setSmoothing(_ seconds: Int) { model.settingsStore.settings.smoothingSeconds = Double(seconds) }
    private func setSlowdown(_ factor: Int) { model.settingsStore.settings.slowdownFactor = Double(factor) }

    @ViewBuilder
    private var revertBlock: some View {
        @Bindable var store = model.settingsStore
                if let previous = store.previousSettings, let date = store.previousSavedAt {
            Button {
                store.revertToPrevious()
            } label: {
                Label("Вернуть прежние", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            let diff = RecommendationText.differences(from: previous, to: store.settings)
            Text(diff.isEmpty
                 ? String(localized: "Настройки совпадают с прежними.")
                 : String(localized: "Изменены \(date.formatted(.dateTime.day().month())): ") + diff.joined(separator: ", ") + ".")
                .font(.caption2)
                .foregroundStyle(palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var cadenceSection: some View {
        @Bindable var store = model.settingsStore
        let settings = store.settings
        sectionTitle("Ритм")
        HStack(spacing: 6) {
            CrownNumberField(title: "Ритм до", value: $store.settings.cadenceMax,
                             range: (settings.cadenceMin + 1)...240, field: .cadenceMax, focused: $focused)
            CrownNumberField(title: "Запас", value: $store.settings.cadenceSpanPercent,
                             range: 1...50, field: .span, focused: $focused, unit: "%")
        }
        HStack(spacing: 6) {
            CrownNumberField(title: "Не ниже", value: $store.settings.cadenceFloor,
                             range: 100...220, field: .floor, focused: $focused)
            Toggle("Автопауза", isOn: $store.settings.autoPause)
                .font(.caption2)
                .foregroundStyle(palette.ink)
        }
    }

    @ViewBuilder
    private var pulseSection: some View {
        @Bindable var store = model.settingsStore
        let settings = store.settings
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
            CrownNumberField(title: "Спуск", value: $slowdown,
                             range: 1...10, field: .slowdown, focused: $focused, unit: "×")
        }
    }

    @ViewBuilder
    private var zonesSection: some View {
        @Bindable var store = model.settingsStore
        let settings = store.settings
        sectionTitle("Зоны и разминка")
        HStack(spacing: 6) {
            CrownNumberField(title: "Возраст", value: $store.settings.age,
                             range: 10...100, field: .age, focused: $focused)
            CrownNumberField(title: "Покой", value: $store.settings.restingHeartRate,
                             range: 30...120, field: .resting, focused: $focused)
        }
        let zones = HeartRateZones.karvonen(age: settings.age, restingHeartRate: settings.restingHeartRate)
        Text("Зона 2: \(zones.zone2Low)–\(zones.zone2High), максимум \(zones.maxHeartRate)")
            .font(.caption2)
            .foregroundStyle(palette.inkSecondary)
        if zones.target != settings.heartRateMax {
            Button("Цель \(zones.target)") {
                store.applyRecommendation { s in
                    s.heartRateMax = zones.target
                    s.heartRateMin = zones.lower
                }
            }
            .font(.caption)
        }
        CrownNumberField(title: "Разминка", value: $warmupMinutes,
                         range: 0...30, field: .warmup, focused: $focused, unit: "мин")
    }

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var store = model.settingsStore
                sectionTitle("Оформление")
        Toggle("Тёмная тема", isOn: Binding(
            get: { store.settings.theme == .dark },
            set: { store.settings.theme = $0 ? .dark : .light }
        ))
        .font(.caption)
        .foregroundStyle(palette.ink)
    }

    @ViewBuilder
    private var soundSection: some View {
        @Bindable var store = model.settingsStore
                sectionTitle("Звук")
        Toggle("Каждый второй шаг", isOn: $store.settings.halfTimeClick)
            .font(.caption)
            .foregroundStyle(palette.ink)
        Slider(value: $store.settings.clickVolume, in: 0...1) {
            Text("Громкость")
        }
        Text("Громкость")
            .font(.caption2)
            .foregroundStyle(palette.inkSecondary)
    }

    @ViewBuilder
    private var voiceSection: some View {
        @Bindable var store = model.settingsStore
                sectionTitle("Голос")
        Toggle("Подсказки голосом", isOn: $store.settings.voiceCues)
            .font(.caption)
            .foregroundStyle(palette.ink)
        CrownNumberField(title: "Повтор «сбавь»", value: $store.settings.voiceRepeatSeconds,
                         range: 0...120, field: .voiceRepeat, focused: $focused, unit: "с")
    }

    @ViewBuilder
    private var developerSection: some View {
        @Bindable var store = model.settingsStore
                sectionTitle("Разработчик")
        if RegulatorSettings.telemetryForcedOn {
            Text("Телеметрия включена в тестовых сборках")
                .font(.caption2)
                .foregroundStyle(palette.inkSecondary)
        } else {
            Toggle("Телеметрия в файл", isOn: $store.settings.developerMode)
                .font(.caption)
                .foregroundStyle(palette.ink)
        }
        HStack(spacing: 6) {
            CrownNumberField(title: "Включение", value: $store.settings.armSeconds,
                             range: 0...300, field: .arm, focused: $focused, unit: "с")
            CrownNumberField(title: "Подъём", value: $ascentPercent,
                             range: 10...100, field: .ascent, focused: $focused, unit: "%")
        }
        Toggle("Проба отклика", isOn: $store.settings.responseProbe)
            .font(.caption)
            .foregroundStyle(palette.ink)
        HStack(spacing: 6) {
            CrownNumberField(title: "Прогноз", value: $store.settings.predictSeconds,
                             range: 0...120, field: .predict, focused: $focused, unit: "с")
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
            .foregroundStyle(palette.inkSecondary)
            .multilineTextAlignment(.center)
    
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}
