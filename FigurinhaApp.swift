import SwiftUI
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import SDWebImageWebPCoder   // SPM: https://github.com/SDWebImage/SDWebImageWebPCoder

@main
struct FigurinhaApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
    }
}

final class Store: ObservableObject {
    @Published var stickers: [Sticker] = []
    @Published var packName = "Minhas Figurinhas"
}

struct RootView: View {
    @StateObject var store = Store()
    var body: some View {
        TabView {
            EditorView().tabItem { Label("Criar", systemImage: "wand.and.stars") }
            PackView().tabItem { Label("Pacote", systemImage: "square.grid.2x2") }
        }
        .environmentObject(store)
        .tint(Theme.accent)
    }
}

