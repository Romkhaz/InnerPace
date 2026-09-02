import SwiftUI

struct WatchRootView: View {
    @Environment(WatchRunModel.self) private var model
    @State private var page = 1

    var body: some View {
        switch model.phase {
        case .setup:
            NavigationStack {
                SetupView()
            }
        case .starting:
            ProgressView("Запуск…")
        case .finishing:
            ProgressView("Сохраняю…")
        case .running, .paused:
            TabView(selection: $page) {
                ControlsView().tag(0)
                MetricsView().tag(1)
            }
            .tabViewStyle(.verticalPage)
            .onAppear { page = 1 }
        }
    }
}
