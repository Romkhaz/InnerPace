import SwiftUI

@main
struct InnerPaceApp: App {
    @State private var session = RunSession(settingsStore: SettingsStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
