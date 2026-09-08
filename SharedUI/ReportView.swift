import SwiftUI

/// Отчёт о тренировке. Один и тот же на телефоне и часах.
struct ReportView: View {
    @Environment(\.palette) private var palette
    let summary: WorkoutSummary
    /// Хранилище настроек этого устройства: даёт кнопки «Применить». Без него отчёт только показывает.
    var settingsStore: SettingsStore? = nil
    /// История пробежек для профиля бегуна, от новых к старым.
    var history: [WorkoutSummary] = []
    var onDone: (() -> Void)? = nil
    @State private var appliedLimits = false
    @State private var appliedProfile = false

    var body: some View {
        List {
            Section {
                row("Дистанция", formatDistance(summary.distanceMeters))
                row("Время", formatElapsed(summary.duration))
                row("Средний темп", formatPace(summary.averagePaceSecondsPerKm), unit: "мин/км")
            }
            Section {
                row("Средний пульс", summary.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                row("Средний каденс", summary.averageCadence.map { "\(Int($0.rounded()))" } ?? "—", unit: "SPM")
                row("Средний ритм", summary.averageMetronome.map { "\(Int($0.rounded()))" } ?? "—", unit: "BPM")
            }
            Section {
                row("Эффективность", formatEfficiency(summary.efficiencyMetersPerBeat), unit: "м/удар")
                if let contact = summary.averageGroundContactMs {
                    row("Контакт с землёй", "\(Int(contact.rounded()))", unit: "мс")
                }
                if let oscillation = summary.averageVerticalOscillationCm {
                    row("Верт. колебания", oscillation.formatted(.number.precision(.fractionLength(1))), unit: "см")
                }
            }
            if let assessment = summary.assessment {
                effortSection(assessment)
            }
            profileSection
            if let onDone {
                Section {
                    Button(action: onDone) {
                        Label("Готово", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.orange)
                    .listRowBackground(palette.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(Text(summary.date, format: .dateTime.day().month().hour().minute()))
    }

    private var settings: RegulatorSettings { settingsStore?.settings ?? .default }

    private var profile: ProfileRecommendation? {
        let estimates = history.sorted { $0.date > $1.date }.compactMap(\.response)
        return ProfileRecommendation.make(from: estimates, settings: settings)
    }

    @ViewBuilder
    private func effortSection(_ a: EffortAssessment) -> some View {
        Section("Усилие") {
            Text(RecommendationText.effort(a, settings: settings))
                .font(.footnote)
                .foregroundStyle(palette.ink)
                .listRowBackground(palette.card)
            if let store = settingsStore, a.hasSuggestion, let suggestion = RecommendationText.effortSuggestion(a, settings: store.settings) {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundStyle(palette.inkSecondary)
                    .listRowBackground(palette.card)
                applyButton(applied: appliedLimits) {
                    store.applyRecommendation { s in
                        if let c = a.suggestedCadenceMin { s.setCadenceMinDerivingMax(c) }
                        if let t = a.suggestedTargetHeartRate { s.setTargetHeartRateKeepingZoneWidth(t) }
                    }
                    appliedLimits = true
                }
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section("Профиль") {
            if let p = profile {
                Text(RecommendationText.profile(p, settings: settings))
                    .font(.footnote)
                    .foregroundStyle(palette.ink)
                    .listRowBackground(palette.card)
                if let store = settingsStore, p.hasSuggestion, let suggestion = RecommendationText.profileSuggestion(p, settings: store.settings) {
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(palette.inkSecondary)
                        .listRowBackground(palette.card)
                    applyButton(applied: appliedProfile) {
                        store.applyRecommendation { s in
                            if let v = p.predictSeconds { s.predictSeconds = v }
                            if let v = p.smoothingSeconds { s.smoothingSeconds = v }
                        }
                        appliedProfile = true
                    }
                }
            } else {
                Text(RecommendationText.profilePending(runs: history.filter { $0.response != nil }.count,
                                                       lastEstimated: summary.response != nil,
                                                       probeEnabled: settings.responseProbe))
                    .font(.footnote)
                    .foregroundStyle(palette.inkSecondary)
                    .listRowBackground(palette.card)
            }
        }
    }

    private func applyButton(applied: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(applied ? "Применено" : "Применить к следующей пробежке",
                  systemImage: applied ? "checkmark.circle.fill" : "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .disabled(applied)
        .buttonStyle(.bordered)
        .tint(palette.orange)
        .listRowBackground(palette.card)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, unit: LocalizedStringKey? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(palette.ink)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.ink)
            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(palette.inkSecondary)
            }
        }
        .listRowBackground(palette.card)
    }
}

/// Метров на удар с двумя знаками.
func formatEfficiency(_ value: Double?) -> String {
    guard let value, value.isFinite, value > 0 else { return "—" }
    return value.formatted(.number.precision(.fractionLength(2)))
}
