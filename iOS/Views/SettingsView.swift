import SwiftUI

/// Основные настройки: нижняя граница ритма и целевой пульс.
/// Всё остальное считается автоматически или живёт в «Дополнительно».
struct SettingsView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        @Bindable var store = session.settingsStore
        let settings = store.settings
        let cadenceMin = Binding<Int>(
            get: { store.settings.cadenceMin },
            set: { store.settings.setCadenceMinDerivingMax($0) }
        )
        let heartRateMax = Binding<Int>(
            get: { store.settings.heartRateMax },
            set: { store.settings.setTargetHeartRateKeepingZoneWidth($0) }
        )
        Form {
            Section("Ритм, ударов в минуту") {
                AdjustRow(title: "Ритм от", value: cadenceMin, range: 100...220)
                Text("Верхняя граница считается автоматически: \(settings.cadenceMax) BPM, это плюс \(settings.cadenceSpanPercent) %.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Пульс") {
                AdjustRow(title: "Целевой пульс", value: heartRateMax, range: 80...210)
                Text("Регулятор ведёт пульс к этой цели. Рост ритма замедляется с \(Int(settings.approachHeartRate)) и останавливается с \(Int(settings.holdHeartRate)).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    Label("Дополнительно", systemImage: "slider.horizontal.3")
                }
            }
            if session.state == .paused {
                Section {
                    Text("Тренировка на паузе: новые границы применятся при продолжении.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Настройки")
    }
}

/// Тонкие параметры регулятора, разминка и звук.
struct AdvancedSettingsView: View {
    @Environment(RunSession.self) private var session
    @State private var previewing = false
    @State private var interval: Int = 5
    @State private var smoothing: Int = 10

    var body: some View {
        @Bindable var store = session.settingsStore
        let settings = store.settings
        Form {
            Section("Ритм") {
                AdjustRow(title: "Ритм до", value: $store.settings.cadenceMax,
                          range: (settings.cadenceMin + 1)...240)
                AdjustRow(title: "Запас над нижней границей", value: $store.settings.cadenceSpanPercent,
                          range: 1...50, unit: "%")
                Text("Запас используется, когда меняете нижнюю границу на главном экране настроек.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Пульс") {
                AdjustRow(title: "Нижняя граница зоны", value: $store.settings.heartRateMin,
                          range: 40...(settings.heartRateMax - 1))
                AdjustRow(title: "Зона подхода", value: $store.settings.approachPercent, range: 0...30, unit: "%")
                AdjustRow(title: "Полоса удержания", value: $store.settings.holdBand, range: 0...20)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Спуск быстрее подъёма")
                        Spacer()
                        Text("×\(settings.slowdownFactor.formatted(.number.precision(.fractionLength(1))))")
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                    Slider(value: $store.settings.slowdownFactor, in: 1...3, step: 0.5)
                }
                Text("В зоне подхода ритм растёт по одному удару за интервал, в полосе удержания не растёт. Выше цели ритм падает быстрее, чем рос.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Темп подстройки") {
                AdjustRow(title: "Разминка", value: $store.settings.warmupMinutes, range: 0...15, unit: "мин")
                AdjustRow(title: "Интервал", value: $interval, range: 2...30, unit: "с")
                AdjustRow(title: "Макс. шаг", value: $store.settings.maxStep, range: 1...10, unit: "уд/мин")
                AdjustRow(title: "Сглаживание пульса", value: $smoothing, range: 0...30, unit: "с")
                Text("На разминке ритм держится на середине диапазона и не разгоняется.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Звук") {
                Toggle("Щелчок на каждый второй шаг", isOn: $store.settings.halfTimeClick)
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $store.settings.clickVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                Toggle("Проверить звук", isOn: $previewing)
                    .disabled(session.state != .idle)
            }
            Section {
                Button("Забыть пульсометр", role: .destructive) {
                    session.polar.forgetDevice()
                }
            }
        }
        .navigationTitle("Дополнительно")
        .onAppear {
            interval = Int(settings.adjustInterval)
            smoothing = Int(settings.smoothingSeconds)
        }
        .onChange(of: interval) { _, new in store.settings.adjustInterval = TimeInterval(new) }
        .onChange(of: smoothing) { _, new in store.settings.smoothingSeconds = Double(new) }
        .onChange(of: previewing) { _, on in session.previewClick(on) }
        .onDisappear {
            if previewing {
                previewing = false
                session.previewClick(false)
            }
        }
    }
}
