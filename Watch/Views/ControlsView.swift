import SwiftUI

/// Страница управления, как в стандартной «Тренировке»: стоп и пауза.
struct ControlsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                roundButton(icon: "xmark", title: "Стоп", color: ZoneStyle.stopRed) {
                    Task { await model.end() }
                }
                roundButton(
                    icon: model.phase == .paused ? "play.fill" : "pause.fill",
                    title: model.phase == .paused ? "Дальше" : "Пауза",
                    color: ZoneStyle.startBlue
                ) {
                    Task { await model.togglePause() }
                }
            }
            if let decision = model.lastDecision {
                Text(decision)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = model.errorText {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func roundButton(icon: String, title: LocalizedStringKey, color: Color,
                             action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(color, in: Circle())
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
