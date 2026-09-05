import SwiftUI

/// Страница управления: стоп, пауза и настройки, доступные прямо на бегу.
struct ControlsView: View {
    @Environment(\.palette) private var palette
    @Environment(WatchRunModel.self) private var model
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    roundButton(icon: "xmark", title: "Стоп", color: palette.stopColor) {
                        Task { await model.end() }
                    }
                    roundButton(
                        icon: model.phase == .paused ? "play.fill" : "pause.fill",
                        title: model.phase == .paused ? "Дальше" : "Пауза",
                        color: palette.startColor
                    ) {
                        Task { await model.togglePause() }
                    }
                }
                Button {
                    showsSettings = true
                } label: {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                if let error = model.errorText {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(palette.deepCoral)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 8) {
                        QuickSettingsView()
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
                .navigationTitle("Настройки")
                .containerBackground(palette.background.gradient, for: .navigation)
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
                .foregroundStyle(palette.inkSecondary)
        }
    }
}
