import SwiftUI

struct ContentView: View {
    @Environment(RunSession.self) private var session

    var body: some View {
        NavigationStack {
            RunView()
                .navigationTitle("InnerPace")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
        }
    }
}
