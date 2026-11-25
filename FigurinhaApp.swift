import SwiftUI

@main
struct FigurinhaApp: App {
    @StateObject private var theme = AppTheme()
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(store)
                .preferredColorScheme(theme.scheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var theme: AppTheme

    var body: some View {
        TabView {
            EditorView()
                .tabItem { Label("Criar", systemImage: "wand.and.stars") }
            PackView()
                .tabItem { Label("Pacote", systemImage: "square.grid.2x2") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "paintpalette") }
        }
        .tint(theme.accent)
    }
}
