import SwiftUI
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import SDWebImageWebPCoder   // SPM: https://github.com/SDWebImage/SDWebImageWebPCoder

struct PackView: View {
    @EnvironmentObject var store: Store
    let cols = [GridItem(.adaptive(minimum: 90), spacing: 10)]
    @StateObject private var audio = AudioManager()
    @State private var shareItem: ShareItem?
    @State private var exporting = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                TextField("Nome do pacote", text: $store.packName)
                    .padding(10).background(Theme.card).cornerRadius(12)
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(store.stickers) { s in
                            Image(uiImage: s.image).resizable().scaledToFit()
                                .padding(6).background(Theme.card).cornerRadius(14)
                                .overlay(alignment: .topTrailing) {
                                    if s.audioURL != nil {
                                        Image(systemName: "speaker.wave.2.fill").font(.caption)
                                            .foregroundColor(Theme.accent).padding(6)
                                    }
                                }
                                .onTapGesture { if let u = s.audioURL { audio.play(u) } }
                                .contextMenu {
                                    if s.audioURL != nil {
                                        Button("Exportar com som (vídeo)") { export(s) }
                                    }
                                    Button("Excluir", role: .destructive) {
                                        store.stickers.removeAll { $0.id == s.id }
                                    }
                                }
                        }
                    }
                }
                Text(exporting ? "Gerando vídeo com som…" : "Mínimo de 3 figurinhas • toque para ouvir • segure para excluir/exportar")
                    .font(.footnote).foregroundColor(Theme.soft)
                Button(action: importToWhatsApp) {
                    Label("Importar para o WhatsApp", systemImage: "square.and.arrow.down.fill")
                        .fontWeight(.semibold).foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity).padding()
                        .background(store.stickers.count >= 3 ? Theme.accent : Color.gray)
                        .cornerRadius(16)
                }.disabled(store.stickers.count < 3)
            }.padding()
        }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
    }

    func export(_ s: Sticker) {
        guard let a = s.audioURL else { return }
        exporting = true
        Task {
            if let u = try? await StickerVideoExporter.export(image: s.image, audio: a) {
                shareItem = ShareItem(url: u)
            }
            exporting = false
        }
    }

    func webp(_ img: UIImage, quality: Double = 0.7) -> Data? {
        SDImageWebPCoder.shared.encodedData(with: img, format: .webP,
                                            options: [.encodeCompressionQuality: quality])
    }

    func importToWhatsApp() {
        let trayFormat = UIGraphicsImageRendererFormat()
        trayFormat.scale = 1
        let trayRenderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: trayFormat)
        let trayImage = trayRenderer.image { _ in
            store.stickers[0].image.draw(in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        guard let trayPNG = trayImage.pngData() else { return }
        let tray = trayPNG.base64EncodedString()

        let stickers: [[String: Any]] = store.stickers.prefix(30).compactMap { s in
            var q = 0.8
            var data = self.webp(s.image, quality: q)
            while let d = data, d.count > 100_000, q > 0.1 {
                q -= 0.1
                data = self.webp(s.image, quality: q)
            }
            guard let d = data else { return nil }
            let item: [String: Any] = ["image_data": d.base64EncodedString(), "emojis": [s.emoji]]
            return item
        }
        let json: [String: Any] = [
            "identifier": UUID().uuidString, "name": store.packName, "publisher": "Figurinha App",
            "tray_image": tray, "ios_app_store_link": "", "android_play_store_link": "",
            "stickers": stickers]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        UIPasteboard.general.setItems([["net.whatsapp.third-party.sticker-pack": data]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        if let url = URL(string: "whatsapp://stickerPack") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
