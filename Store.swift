import SwiftUI
import UIKit

// MARK: - Modelo de figurinha
struct Sticker: Identifiable {
    var id = UUID()
    var image: UIImage          // 512x512 (primeiro quadro, se animada)
    var webp: Data              // WebP pronto para o WhatsApp (estático ou animado)
    var animated: Bool
    var emoji = "😀"
    var audioURL: URL? = nil    // áudio gravado/importado
    var videoURL: URL? = nil    // MP4 com som (para criar a figurinha de som no WhatsApp)

    var soundURL: URL? { audioURL ?? videoURL }
    var hasSound: Bool { soundURL != nil }
}

// MARK: - Pacote salvo no aparelho (não perde ao fechar o app)
final class Store: ObservableObject {
    @Published var stickers: [Sticker] = []
    @Published var packName = "Minhas Figurinhas" {
        didSet { if !loading { saveIndex() } }
    }

    private var loading = false
    private let dir: URL

    private struct Meta: Codable {
        var id: String
        var emoji: String
        var animated: Bool
        var audioFile: String?
        var videoFile: String?
    }
    private struct Index: Codable {
        var packName: String
        var items: [Meta]
    }

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("pack", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func add(_ sticker: Sticker) {
        var s = sticker
        let fm = FileManager.default
        let id = s.id.uuidString

        if let a = s.audioURL {
            let ext = a.pathExtension.isEmpty ? "m4a" : a.pathExtension
            let dest = dir.appendingPathComponent("\(id).audio.\(ext)")
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: a, to: dest)) != nil { s.audioURL = dest }
        }
        if let v = s.videoURL {
            let dest = dir.appendingPathComponent("\(id).mp4")
            try? fm.removeItem(at: dest)
            if (try? fm.copyItem(at: v, to: dest)) != nil { s.videoURL = dest }
        }
        try? s.image.pngData()?.write(to: dir.appendingPathComponent("\(id).png"))
        try? s.webp.write(to: dir.appendingPathComponent("\(id).webp"))

        stickers.append(s)
        saveIndex()
    }

    func remove(_ id: UUID) {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
            for f in files where f.hasPrefix(id.uuidString) {
                try? fm.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        stickers.removeAll { $0.id == id }
        saveIndex()
    }

    func setEmoji(_ id: UUID, _ emoji: String) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[i].emoji = emoji
        saveIndex()
    }

    private func saveIndex() {
        let items: [Meta] = stickers.map { s in
            Meta(id: s.id.uuidString, emoji: s.emoji, animated: s.animated,
                 audioFile: s.audioURL?.lastPathComponent,
                 videoFile: s.videoURL?.lastPathComponent)
        }
        let idx = Index(packName: packName, items: items)
        if let data = try? JSONEncoder().encode(idx) {
            try? data.write(to: dir.appendingPathComponent("index.json"), options: .atomic)
        }
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
              let idx = try? JSONDecoder().decode(Index.self, from: data) else { return }
        packName = idx.packName
        var out: [Sticker] = []
        for m in idx.items {
            guard let uuid = UUID(uuidString: m.id),
                  let img = UIImage(contentsOfFile: dir.appendingPathComponent("\(m.id).png").path),
                  let webp = try? Data(contentsOf: dir.appendingPathComponent("\(m.id).webp"))
            else { continue }
            var s = Sticker(id: uuid, image: img, webp: webp, animated: m.animated, emoji: m.emoji)
            if let f = m.audioFile { s.audioURL = dir.appendingPathComponent(f) }
            if let f = m.videoFile { s.videoURL = dir.appendingPathComponent(f) }
            out.append(s)
        }
        stickers = out
    }
}
