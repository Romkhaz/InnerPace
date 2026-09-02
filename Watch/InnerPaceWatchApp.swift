import SwiftUI

@main
struct InnerPaceWatchApp: App {
    @State private var model = WatchRunModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
        }
    }
}
