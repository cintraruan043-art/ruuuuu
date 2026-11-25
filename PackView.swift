import SwiftUI
import Photos
import UIKit

struct IDBox: Identifiable { let id: UUID }

struct PackView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: AppTheme
    @StateObject private var audio = AudioManager()
    @State private var shareItem: ShareItem?
    @State private var emojiTarget: IDBox?
    @State private var showChoice = false
    @State private var alertText: String?

    let cols = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var animatedCount: Int { store.stickers.filter { $0.animated }.count }
    var staticCount: Int { store.stickers.filter { !$0.animated }.count }
    var canImport: Bool { animatedCount >= 3 || staticCount >= 3 }
    var hasSound: Bool { store.stickers.contains { $0.hasSound } }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                VStack(spacing: 12) {
                    TextField("Nome do pacote", text: $store.packName)
                        .padding(12)
                        .foregroundColor(theme.text)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("\(store.stickers.count) figurinhas · \(animatedCount) animadas · \(staticCount) estáticas")
                        .font(.footnote).foregroundColor(theme.soft)

                    if store.stickers.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundColor(theme.accent)
                            Text("Nenhuma figurinha ainda.\nCrie na aba Criar.")
                                .multilineTextAlignment(.center).foregroundColor(theme.soft)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(store.stickers) { s in cell(s) }
                            }
                            if hasSound { soundInfo.padding(.top, 8) }
                        }
                    }

                    Text("Mínimo de 3 do mesmo tipo (animadas e estáticas não se misturam) · toque para ouvir · segure para opções")
                        .font(.caption2).multilineTextAlignment(.center).foregroundColor(theme.soft)

                    PrimaryButton(title: "Importar para o WhatsApp",
                                  icon: "square.and.arrow.down.fill",
                                  enabled: canImport) { tapImport() }
                }
                .padding()
            }
            .navigationTitle("Meu pacote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.bg, for: .navigationBar)
        }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        .sheet(item: $emojiTarget) { box in
            EmojiSheet { e in store.setEmoji(box.id, e) }
                .environmentObject(theme)
                .presentationDetents([.medium])
        }
        .confirmationDialog("O WhatsApp não aceita pacote misto",
                            isPresented: $showChoice, titleVisibility: .visible) {
            if animatedCount >= 3 {
                Button("Importar só as animadas (\(animatedCount))") { send(animated: true) }
            }
            if staticCount >= 3 {
                Button("Importar só as estáticas (\(staticCount))") { send(animated: false) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Aviso", isPresented: Binding(
            get: { alertText != nil },
            set: { if !$0 { alertText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
    }

    // MARK: Célula
    func cell(_ s: Sticker) -> some View {
        Image(uiImage: s.image)
            .resizable().scaledToFit()
            .padding(6)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                if s.animated {
                    Image(systemName: "play.circle.fill").font(.caption)
                        .foregroundColor(theme.accent).padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if s.hasSound {
                    Image(systemName: "speaker.wave.2.fill").font(.caption)
                        .foregroundColor(theme.accent).padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(s.emoji).font(.caption).padding(6)
            }
            .onTapGesture { if let u = s.soundURL { audio.play(u) } }
            .contextMenu {
                Button { emojiTarget = IDBox(id: s.id) } label: {
                    Label("Trocar emoji", systemImage: "face.smiling")
                }
                if let v = s.videoURL {
                    Button { shareItem = ShareItem(url: v) } label: {
                        Label("Enviar vídeo com som", systemImage: "square.and.arrow.up")
                    }
                    Button { saveToPhotos(v) } label: {
                        Label("Salvar vídeo na galeria", systemImage: "photo.badge.arrow.down")
                    }
                }
                Button(role: .destructive) { store.remove(s.id) } label: {
                    Label("Excluir", systemImage: "trash")
                }
            }
    }

    var soundInfo: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Figurinhas com som", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold)).foregroundColor(theme.accent)
                Text("Segure a figurinha com 🔊 → \"Salvar vídeo na galeria\". Depois, no WhatsApp: abra uma conversa → figurinhas → criar → escolha esse vídeo e deixe o som ligado.")
                    .font(.caption).foregroundColor(theme.soft)
                Text("A importação em pacote ainda não leva o som: o WhatsApp avisou, no repositório oficial de stickers, que essa API para apps de terceiros ainda não existe.")
                    .font(.caption).foregroundColor(theme.soft)
            }
        }
    }

    // MARK: Ações
    func tapImport() {
        if animatedCount > 0 && staticCount > 0 { showChoice = true }
        else { send(animated: animatedCount > 0) }
    }

    func send(animated: Bool) {
        let list = store.stickers.filter { $0.animated == animated }
        guard list.count >= 3 else {
            alertText = "Precisa de pelo menos 3 figurinhas desse tipo."
            return
        }
        guard let payload = WhatsAppExporter.payload(name: store.packName, stickers: list, animated: animated) else {
            alertText = "Não consegui montar o pacote."
            return
        }
        UIPasteboard.general.setItems(
            [["net.whatsapp.third-party.sticker-pack": payload]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        Task {
            guard let url = URL(string: "whatsapp://stickerPack") else { return }
            let ok = await UIApplication.shared.open(url)
            if !ok { alertText = "Não consegui abrir o WhatsApp. Ele está instalado?" }
        }
    }

    func saveToPhotos(_ url: URL) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                alertText = "Permita o acesso às fotos em Ajustes para salvar o vídeo."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                alertText = "Vídeo salvo na galeria! Agora, no WhatsApp: conversa → figurinhas → criar → escolha esse vídeo."
            } catch {
                alertText = "Não consegui salvar o vídeo."
            }
        }
    }
}

// MARK: - Monta o pacote no formato da API de stickers do WhatsApp
enum WhatsAppExporter {
    static func payload(name: String, stickers: [Sticker], animated: Bool) -> Data? {
        guard let first = stickers.first else { return nil }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let trayImage = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: f).image { _ in
            first.image.draw(in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        guard let png = trayImage.pngData() else { return nil }

        var items: [[String: Any]] = []
        for s in stickers.prefix(30) {
            items.append(["image_data": s.webp.base64EncodedString(), "emojis": [s.emoji]])
        }
        let json: [String: Any] = [
            "identifier": UUID().uuidString,
            "name": name.isEmpty ? "Figurinhas" : name,
            "publisher": "Figurinha App",
            "tray_image": png.base64EncodedString(),
            "ios_app_store_link": "",
            "android_play_store_link": "",
            "is_animated_sticker_pack": animated,
            "stickers": items
        ]
        return try? JSONSerialization.data(withJSONObject: json)
    }
}

// MARK: - Escolher emoji
struct EmojiSheet: View {
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

    private let emojis = ["😀","😂","🤣","😍","🥰","😎","🤩","😭","😡","🥳","🤔","😴",
                          "👍","👏","🙏","💪","🔥","❤️","💔","✨","🎉","💀","👀","🙌",
                          "🤝","😅","😬","🤯","🥺","😈","🤡","👻","🐶","🐱","🍕","⚽️"]

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                Text("Emoji da figurinha").font(.headline).foregroundColor(theme.text).padding(.top, 16)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(emojis, id: \.self) { e in
                        Button { onPick(e); dismiss() } label: {
                            Text(e).font(.largeTitle)
                        }
                    }
                }
                .padding()
            }
        }
    }
}
