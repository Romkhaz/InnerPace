import SwiftUI

/// Страница управления, как в стандартной «Тренировке»: стоп и пауза.
struct ControlsView: View {
    @Environment(WatchRunModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack {
                    Button {
                        Task { await model.end() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                    }
                    .tint(.red)
                    Text("Стоп")
                        .font(.caption2)
                }
                VStack {
                    Button {
                        Task { await model.togglePause() }
                    } label: {
                        Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                    }
                    .tint(.yellow)
                    Text(model.phase == .paused ? "Дальше" : "Пауза")
                        .font(.caption2)
                }
            }
            .buttonStyle(.borderedProminent)

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
}
