import SwiftUI

/// Тексты и кнопки рекомендаций после пробежки. Общие для телефона и часов.
enum RecommendationText {
    static func effort(_ a: EffortAssessment, settings: RegulatorSettings) -> String {
        let floor = Int((a.shareAtFloor * 100).rounded())
        let above = Int((a.shareAboveTarget * 100).rounded())
        let band = Int((a.shareInBand * 100).rounded())
        switch a.verdict {
        case .insufficient:
            return String(localized: "Регулятор работал \(a.regulatedSeconds / 60) мин, для выводов нужно хотя бы \(EffortAssessment.minimumSeconds / 60).")
        case .onLimit:
            var text = String(localized: "Вы бежали на пределе: ритм \(floor) % времени стоял на нижней границе, пульс \(above) % времени выше цели.")
            if let lever = a.cadenceLever, lever < EffortAssessment.weakLever {
                text += " " + String(localized: "Ритм на пульс почти не влиял, его задаёт темп: бегите медленнее или поднимите допустимый пульс.")
            } else {
                text += " " + String(localized: "Бегите медленнее, снизьте минимальный ритм или поднимите допустимый пульс.")
            }
            return text
        case .reserve:
            return String(localized: "Есть запас: пульс \(band) % времени в полосе удержания и почти не поднимался выше цели. Можно бежать быстрее, оставаясь в зоне: поднимите минимальный ритм.")
        case .balanced:
            return String(localized: "Пределы подобраны нормально: пульс \(band) % времени в полосе удержания, выше цели \(above) %, ритм на нижней границе \(floor) %.")
        }
    }

    static func effortSuggestion(_ a: EffortAssessment, settings: RegulatorSettings) -> String? {
        var parts: [String] = []
        if let c = a.suggestedCadenceMin { parts.append(String(localized: "ритм от \(settings.cadenceMin) на \(c)")) }
        if let t = a.suggestedTargetHeartRate { parts.append(String(localized: "пульс до \(settings.targetHeartRate) на \(t)")) }
        guard !parts.isEmpty else { return nil }
        return String(localized: "На следующую пробежку: ") + parts.joined(separator: ", ")
    }

    static func profile(_ p: ProfileRecommendation, settings: RegulatorSettings) -> String {
        let gain = p.gainPerStep.formatted(.number.precision(.fractionLength(1)))
        var text = String(localized: "По \(p.runsUsed) пробежкам: половина отклика пульса на ритм приходит через \(Int(p.lagSeconds)) с, около \(gain) удара на шаг, разброс датчика \(p.noise.formatted(.number.precision(.fractionLength(1)))).")
        if !p.hasSuggestion {
            text += " " + String(localized: "Параметры расчёта менять не нужно.")
        }
        return text
    }

    static func profileSuggestion(_ p: ProfileRecommendation, settings: RegulatorSettings) -> String? {
        var parts: [String] = []
        if let s = p.predictSeconds { parts.append(String(localized: "прогноз \(settings.predictSeconds) на \(s) с")) }
        if let s = p.smoothingSeconds { parts.append(String(localized: "сглаживание \(Int(settings.smoothingSeconds)) на \(Int(s)) с")) }
        guard !parts.isEmpty else { return nil }
        return String(localized: "Предлагаю: ") + parts.joined(separator: ", ")
    }

    static func profilePending(runs: Int, lastEstimated: Bool, probeEnabled: Bool) -> String {
        var text = String(localized: "Профиль появится после \(ProfileRecommendation.minimumRuns) пробежек, где удалось оценить отклик пульса на ритм, пока \(runs).")
        if !lastEstimated {
            text += " " + (probeEnabled
                ? String(localized: "В этой пробежке проба отклика не состоялась: для неё пульс должен минуту ровно держаться в полосе удержания.")
                : String(localized: "В этой пробежке отклик не виден. Включите пробу отклика в дополнительных настройках."))
        }
        return text
    }

    /// Чем прежние настройки отличаются от текущих, для подписи под кнопкой возврата.
    static func differences(from previous: RegulatorSettings, to current: RegulatorSettings) -> [String] {
        var out: [String] = []
        if previous.cadenceMin != current.cadenceMin { out.append(String(localized: "ритм от \(current.cadenceMin) вернётся на \(previous.cadenceMin)")) }
        if previous.cadenceMax != current.cadenceMax { out.append(String(localized: "ритм до \(current.cadenceMax) вернётся на \(previous.cadenceMax)")) }
        if previous.heartRateMax != current.heartRateMax { out.append(String(localized: "пульс до \(current.heartRateMax) вернётся на \(previous.heartRateMax)")) }
        if previous.heartRateMin != current.heartRateMin { out.append(String(localized: "пульс от \(current.heartRateMin) вернётся на \(previous.heartRateMin)")) }
        if previous.predictSeconds != current.predictSeconds { out.append(String(localized: "прогноз \(current.predictSeconds) вернётся на \(previous.predictSeconds) с")) }
        if previous.smoothingSeconds != current.smoothingSeconds { out.append(String(localized: "сглаживание \(Int(current.smoothingSeconds)) вернётся на \(Int(previous.smoothingSeconds)) с")) }
        return out
    }
}

/// Кнопка возврата к прежним настройкам с подписью, что изменится. Пустая, если снимка нет.
struct RevertSettingsSection: View {
    @Environment(\.palette) private var palette
    let store: SettingsStore

    var body: some View {
        if let previous = store.previousSettings, let date = store.previousSavedAt {
            Section {
                Button {
                    store.revertToPrevious()
                } label: {
                    Label("Вернуть прежние настройки", systemImage: "arrow.uturn.backward")
                }
                .foregroundStyle(palette.ink)
                let diff = RecommendationText.differences(from: previous, to: store.settings)
                Text(diff.isEmpty
                     ? String(localized: "Настройки совпадают с прежними.")
                     : String(localized: "Изменены \(date.formatted(.dateTime.day().month())): ") + diff.joined(separator: ", ") + ".")
                    .font(.caption2)
                    .foregroundStyle(palette.inkSecondary)
            }
            .listRowBackground(palette.card)
        }
    }
}
