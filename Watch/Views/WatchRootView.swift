import SwiftUI

struct WatchRootView: View {
    @Environment(WatchRunModel.self) private var model
    @State private var page = 1

    var body: some View {
        Group {
            switch model.phase {
            case .setup:
                NavigationStack {
                    SetupView()
                        .containerBackground(ZoneStyle.background.gradient, for: .navigation)
                }
            case .starting:
                ProgressView("Запуск…")
            case .finishing:
                ProgressView("Сохраняю…")
            case .report:
                NavigationStack {
                    if let summary = model.report {
                        ReportView(summary: summary) {
                            model.dismissReport()
                        }
                        .containerBackground(ZoneStyle.background.gradient, for: .navigation)
                    }
                }
            case .running, .paused:
                TabView(selection: $page) {
                    ControlsView().tag(0)
                    MetricsView().tag(1)
                    DetailsView().tag(2)
                }
                .tabViewStyle(.verticalPage)
                .containerBackground(ZoneStyle.background.gradient, for: .tabView)
                .onAppear { page = 1 }
            }
        }
        .tint(ZoneStyle.orange)
    }
}
