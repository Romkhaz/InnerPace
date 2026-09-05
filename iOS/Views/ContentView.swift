import SwiftUI

struct ContentView: View {
    @Environment(RunSession.self) private var session
    @Environment(\.colorScheme) private var systemScheme

    private var palette: Palette {
        Palette.resolve(theme: session.settings.theme, systemIsDark: systemScheme == .dark)
    }

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
                .toolbarBackground(palette.background, for: .navigationBar)
        }
        .tint(palette.orange)
        .environment(\.palette, palette)
        .preferredColorScheme(session.settings.theme == .auto ? nil : (session.settings.theme == .dark ? .dark : .light))
    }
}
