import SwiftUI

struct SettingsView: View {
    @Environment(RunSession.self) private var session
    @State private var previewing = false
    @State private var interval: Int = 5
    @State private var smoothing: Int = 10

    var body: some View {
        @Bindable var store = session.settingsStore
        let settings = store.settings
        Form {
            Section("Каденс, шагов в минуту") {
                AdjustRow(title: "Нижняя граница", value: $store.settings.cadenceMin,
                          range: 100...(settings.cadenceMax - 1))
                AdjustRow(title: "Верхняя граница", value: $store.settings.cadenceMax,
                          range: (settings.cadenceMin + 1)...240)
            }
            Section("Зона пульса") {
                AdjustRow(title: "Нижняя граница", value: $store.settings.heartRateMin,
                          range: 40...(settings.heartRateMax - 1))
                AdjustRow(title: "Целевой пульс", value: $store.settings.heartRateMax,
                          range: (settings.heartRateMin + 1)...220)
                AdjustRow(title: "Полоса удержания", value: $store.settings.holdBand,
                          range: 0...15)
                Text("Регулятор ведёт пульс к целевому значению. В полосе удержания под целью каденс не меняется.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Скорость подстройки") {
                AdjustRow(title: "Интервал", value: $interval, range: 2...30, unit: "с")
                AdjustRow(title: "Макс. шаг", value: $store.settings.maxStep, range: 1...10, unit: "уд/мин")
                AdjustRow(title: "Сглаживание пульса", value: $smoothing, range: 0...30, unit: "с")
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
        .navigationTitle("Настройки")
        .onAppear {
            interval = Int(settings.adjustInterval)
            smoothing = Int(settings.smoothingSeconds)
        }
        .onChange(of: interval) { _, new in
            store.settings.adjustInterval = TimeInterval(new)
        }
        .onChange(of: smoothing) { _, new in
            store.settings.smoothingSeconds = Double(new)
        }
        .onChange(of: previewing) { _, on in
            session.previewClick(on)
        }
        .onDisappear {
            if previewing {
                previewing = false
                session.previewClick(false)
            }
        }
    }
}
