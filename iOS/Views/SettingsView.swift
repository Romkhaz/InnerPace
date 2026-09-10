import SwiftUI

/// Основные настройки: нижняя граница ритма и целевой пульс.
/// Всё остальное считается автоматически или живёт в «Дополнительно».
struct SettingsView: View {
    @Environment(\.palette) private var palette
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
                Text("Верхняя граница считается автоматически: \(settings.cadenceMax) BPM, это плюс \(settings.cadenceSpanPercent) %, но не меньше плюс \(RegulatorSettings.cadenceMinSpanPercent) %.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("На бегу") {
                Toggle("Автопауза", isOn: $store.settings.autoPause)
                Text("Стоите дольше 10 секунд, тренировка сама встаёт на паузу и сама продолжается, когда пошли. После паузы дольше минуты регулятор начинает заново, как на старте.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Пульс") {
                AdjustRow(title: "Целевой пульс", value: heartRateMax, range: 80...210)
                Text("Регулятор ведёт пульс к этой цели. Рост ритма замедляется с \(Int(settings.approachHeartRate)) и останавливается с \(Int(settings.holdHeartRate)).")
                    .font(.footnote).foregroundStyle(.secondary)
                if let warning = RecommendationText.targetWarning(settings) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(palette.deepCoral)
                }
            }
            Section("Зоны и разминка") {
                AdjustRow(title: "Возраст", value: $store.settings.age, range: 10...100)
                AdjustRow(title: "Пульс покоя", value: $store.settings.restingHeartRate, range: 30...120)
                let zones = HeartRateZones.karvonen(age: settings.age, restingHeartRate: settings.restingHeartRate)
                Text(RecommendationText.zones(zones, settings: settings))
                    .font(.footnote).foregroundStyle(.secondary)
                if zones.target != settings.heartRateMax {
                    Button {
                        store.applyRecommendation { s in
                            s.heartRateMax = zones.target
                            s.heartRateMin = zones.lower
                        }
                    } label: {
                        Label("Поставить цель \(zones.target)", systemImage: "target")
                    }
                }
                AdjustRow(title: "Разминка", value: Binding(
                    get: { store.settings.warmupSeconds / 60 },
                    set: { store.settings.warmupSeconds = $0 * 60 }
                ), range: 0...30, unit: "мин")
                Text("Возраст и пульс покоя берутся из Здоровья, если там есть. На разминке ритм стоит на нижней границе, а «сбавь» звучит, если пульс выше цели минус \(RegulatorSettings.warmupMargin). Кнопка «Заминка» на бегу плавно снижает ритм.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            RevertSettingsSection(store: store)
            Section("Оформление") {
                Picker("Тема", selection: $store.settings.theme) {
                    Text("Авто").tag(AppTheme.auto)
                    Text("Светлая").tag(AppTheme.light)
                    Text("Тёмная").tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
                Text("Авто следует за оформлением iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    Label("Дополнительно", systemImage: "slider.horizontal.3")
                }
            }
            if session.state != .idle {
                Section {
                    Text("Тренировка идёт: новые значения применяются сразу.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Настройки")
    }
}

/// Тонкие параметры регулятора, звук и режим разработчика.
struct AdvancedSettingsView: View {
    @Environment(\.palette) private var palette
    @Environment(RunSession.self) private var session
    @State private var previewing = false
    @State private var interval: Int = 5
    @State private var smoothing: Int = 5

    var body: some View {
        @Bindable var store = session.settingsStore
        let settings = store.settings
        Form {
            Section("Ритм") {
                AdjustRow(title: "Ритм до", value: $store.settings.cadenceMax,
                          range: (settings.cadenceMin + 1)...240)
                AdjustRow(title: "Ритм не ниже", value: $store.settings.cadenceFloor, range: 100...220)
                Text("Ниже этого ритма рекомендации нижнюю границу не опускают. По умолчанию порога нет, поставьте свой: низкий каденс травмоопасен.")
                    .font(.footnote).foregroundStyle(.secondary)
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
                Text("Старт с нижней границы ритма. Регулятор включается, когда пульс продержался в зоне подхода полминуты, и дальше работает всю тренировку: в зоне подхода ритм растёт по одному удару за интервал, в полосе удержания не растёт, выше цели падает быстрее, чем рос.")
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
            Section("Голос") {
                Toggle("Подсказки голосом", isOn: $store.settings.voiceCues)
                AdjustRow(title: "Повтор «сбавь»", value: $store.settings.voiceRepeatSeconds, range: 0...120, unit: "с")
                HStack {
                    Image(systemName: "speaker.wave.1.fill")
                    Slider(value: $store.settings.voiceVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                Text("Когда ритм упёрся в нижнюю границу, а пульс выше цели дольше десяти секунд, щелчок становится глуше с двойным ударом на каждый четвёртый такт и звучит «сбавь». Когда пульс вернулся под цель, звучит «в норме». Повтор 0 значит только на переходах.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Разработчик") {
                if RegulatorSettings.telemetryForcedOn {
                    Label("Телеметрия включена в тестовых сборках", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Телеметрия в файл", isOn: $store.settings.developerMode)
                }
                AdjustRow(title: "Включение регулятора", value: $store.settings.armSeconds, range: 0...300, unit: "с")
                AdjustRow(title: "Прогноз пульса", value: $store.settings.predictSeconds, range: 0...120, unit: "с")
                Toggle("Проба отклика", isOn: $store.settings.responseProbe)
                Text("Раз за пробежку, когда пульс минуту ровно держится в полосе удержания, ритм поднимается на \(RegulatorSettings.probeStep) на \(Int(RegulatorSettings.probeSeconds)) с. По отклику пульса считается профиль бегуна. Когда профиль набран, проба выключается сама.")
                    .font(.footnote).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Подъём от базового шага")
                        Spacer()
                        Text("×\(settings.ascentFactor.formatted(.number.precision(.fractionLength(2))))")
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                    Slider(value: $store.settings.ascentFactor, in: 0.1...1, step: 0.05)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Спуск быстрее подъёма")
                        Spacer()
                        Text("×\(settings.slowdownFactor.formatted(.number.precision(.fractionLength(1))))")
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                    Slider(value: $store.settings.slowdownFactor, in: 1...10, step: 0.5)
                }
                AdjustRow(title: "Сглаживание пульса", value: $smoothing, range: 0...30, unit: "с")
                AdjustRow(title: "Интервал", value: $interval, range: 2...30, unit: "с")
                AdjustRow(title: "Макс. шаг", value: $store.settings.maxStep, range: 1...10, unit: "уд/мин")
                Text("Регулятор включается, когда пульс продержался в зоне подхода указанное число секунд. Решение принимается по прогнозу: сглаженный пульс плюс тренд на указанное число секунд вперёд, потому что пульс отвечает на смену ритма с задержкой около минуты. Подъём считается от базового шага с множителем, спуск от базового шага напрямую. Выше цели решение принимается по сырому пульсу без задержки сглаживания. Телеметрия пишется посекундно в CSV, файлы лежат в папке InnerPace в «Файлах» и в «Истории».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Забыть пульсометр", role: .destructive) {
                    session.polar.forgetDevice()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
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
