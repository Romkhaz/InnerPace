import SwiftUI

struct ContentView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        NavigationStack {
            RunView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                .toolbarBackground(ZoneStyle.background, for: .navigationBar)
        }
        .tint(ZoneStyle.orange)
        .preferredColorScheme(.light)
    }
}
