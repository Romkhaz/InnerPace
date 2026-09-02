import SwiftUI

struct SettingsView: View {
    @Environment(RunSession.self) private var session
    @State private var previewing = false

    var body: some View {
        @Bindable var store = session.settingsStore
        Form {
            Section("Каденс, шагов в минуту") {
                Stepper("Нижняя граница: \(store.settings.cadenceMin)", value: $store.settings.cadenceMin, in: 120...220)
                Stepper("Верхняя граница: \(store.settings.cadenceMax)", value: $store.settings.cadenceMax, in: 120...220)
            }
            Section("Зона пульса") {
                Stepper("Нижняя граница: \(store.settings.heartRateMin)", value: $store.settings.heartRateMin, in: 60...210)
                Stepper("Целевой пульс: \(store.settings.heartRateMax)", value: $store.settings.heartRateMax, in: 60...210)
                Stepper("Полоса удержания: \(store.settings.holdBand)", value: $store.settings.holdBand, in: 0...15)
                Text("Регулятор ведёт пульс к целевому значению. В полосе удержания под целью каденс не меняется.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Скорость подстройки") {
                Stepper("Интервал: \(Int(store.settings.adjustInterval)) с", value: $store.settings.adjustInterval, in: 2...30, step: 1)
                Stepper("Макс. шаг: \(store.settings.maxStep) уд/мин", value: $store.settings.maxStep, in: 1...10)
                Stepper("Сглаживание пульса: \(Int(store.settings.smoothingSeconds)) с", value: $store.settings.smoothingSeconds, in: 0...30, step: 1)
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
        .onChange(of: previewing) { _, on in
            session.previewClick(on)
        }
        .onChange(of: store.settings) { _, new in
            let fixed = new.normalized()
            if fixed != new { store.settings = fixed }
        }
        .onDisappear {
            if previewing {
                previewing = false
                session.previewClick(false)
            }
        }
    }
}
