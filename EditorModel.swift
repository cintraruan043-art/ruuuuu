import SwiftUI
import PhotosUI
import AVFoundation
import Vision
import CoreImage
import CoreTransferable
import UniformTypeIdentifiers

// Vídeo escolhido na galeria (copiado para uma pasta temporária)
struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("pick-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    enum Kind { case none, photo, video }

    static let maxClip: Double = 5      // segundos (limite do som em figurinha de vídeo)
    static let fps = 12

    @Published var kind: Kind = .none
    @Published var source: UIImage?
    @Published var params = EditParams()
    @Published var busy = false
    @Published var busyText = ""
    @Published var progress: Double = 0
    @Published var alertMessage: String?

    // vídeo
    @Published var videoURL: URL?
    @Published var duration: Double = 0
    @Published var trimStart: Double = 0
    @Published var trimLength: Double = 3
    @Published var previewFrac: Double = 0
    @Published var hasVideoAudio = false
    @Published var useVideoAudio = true

    // áudio gravado/importado
    @Published var audioURL: URL?

    private var original: UIImage?
    private var thumbTask: Task<Void, Never>?

    // MARK: Carregar mídia
    func load(_ item: PhotosPickerItem) async {
        busy = true; busyText = "Carregando…"; progress = 0
        defer { busy = false }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            guard let v = try? await item.loadTransferable(type: PickedVideo.self) else {
                alertMessage = "Não consegui abrir esse vídeo."
                return
            }
            await setupVideo(v.url)
        } else {
            guard let d = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: d) else {
                alertMessage = "Não consegui abrir essa foto."
                return
            }
            let n = img.normalized(maxSide: 1280)
            kind = .photo
            source = n
            original = n
            params = EditParams()
            videoURL = nil
        }
    }

    private func setupVideo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        guard dur.isFinite, dur > 0.3 else {
            alertMessage = "Vídeo muito curto ou inválido."
            return
        }
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        kind = .video
        videoURL = url
        duration = dur
        trimStart = 0
        trimLength = min(Self.maxClip, dur)
        previewFrac = 0
        hasVideoAudio = !audioTracks.isEmpty
        useVideoAudio = hasVideoAudio
        params = EditParams()
        await refreshThumb()
    }

    // MARK: Trecho do vídeo
    func clampTrim() {
        trimStart = min(max(0, trimStart), max(0, duration - 0.5))
        let maxLen = max(0.5, min(Self.maxClip, duration - trimStart))
        trimLength = min(max(0.5, trimLength), maxLen)
    }

    func scheduleThumb() {
        thumbTask?.cancel()
        thumbTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await refreshThumb()
        }
    }

    func refreshThumb() async {
        guard let url = videoURL else { return }
        let t = trimStart + previewFrac * max(0, trimLength - 0.1)
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1024, height: 1024)
        let tol = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter = tol
        if let r = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
            let img = UIImage(cgImage: r.image)
            source = img
            original = img
        }
    }

    // MARK: Edição
    func resetImage() {
        source = original
    }

    func removeBackground() {
        guard kind == .photo, let img = source, let cg = img.cgImage else { return }
        busy = true; busyText = "Removendo fundo…"; progress = 0
        Task {
            let out: UIImage? = await Task.detached(priority: .userInitiated) {
                EditorModel.cutout(cg)
            }.value
            if let out { source = out }
            else { alertMessage = "Não consegui separar o objeto dessa foto." }
            busy = false
        }
    }

    nonisolated static func cutout(_ cg: CGImage) -> UIImage? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        do {
            try handler.perform([req])
            guard let r = req.results?.first else { return nil }
            let buf = try r.generateMaskedImage(ofInstances: r.allInstances,
                                                from: handler,
                                                croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buf)
            guard let c = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: c)
        } catch {
            return nil
        }
    }

    func reset() {
        thumbTask?.cancel()
        kind = .none
        source = nil
        original = nil
        videoURL = nil
        audioURL = nil
        params = EditParams()
    }

    // MARK: Gerar figurinha
    func buildSticker() async -> Sticker? {
        guard let src = source else { return nil }
        busy = true; progress = 0
        defer { busy = false }
        let p = params

        switch kind {
        case .none:
            return nil

        case .photo:
            busyText = "Gerando figurinha…"
            let img = StickerComposer.render(src, p)
            let data = await Task.detached(priority: .userInitiated) {
                MediaExporter.webpStatic(img)
            }.value
            guard let webp = data else {
                alertMessage = "Falha ao gerar o WebP."
                return nil
            }
            var mp4: URL?
            if let a = audioURL {
                busyText = "Juntando o áudio…"
                let audioLen = await MediaExporter.duration(of: a)
                let dur = max(1, min(audioLen, AudioManager.maxDuration))
                let count = Int(dur * 5) + 1
                let frames = Array(repeating: img, count: count)
                mp4 = try? await MediaExporter.makeMP4(frames: frames, fps: 5, audio: .file(a), duration: dur)
            }
            return Sticker(image: img, webp: webp, animated: false, audioURL: audioURL, videoURL: mp4)

        case .video:
            guard let url = videoURL else { return nil }
            let start = trimStart
            let len = trimLength
            let fps = Self.fps
            let custom = audioURL
            let wantsVideoAudio = useVideoAudio && hasVideoAudio
            do {
                busyText = "Extraindo quadros…"
                let frames = try await MediaExporter.renderVideoFrames(
                    url: url, start: start, length: len, fps: fps, params: p
                ) { v in
                    Task { @MainActor in self.progress = v }
                }
                busyText = "Codificando WebP animado…"
                progress = 0
                let result = await Task.detached(priority: .userInitiated) {
                    MediaExporter.webpAnimated(frames: frames, fps: fps)
                }.value
                guard let r = result else {
                    alertMessage = "Falha ao gerar a figurinha animada."
                    return nil
                }
                if !r.fits {
                    alertMessage = "A figurinha passou de 500 KB e o WhatsApp pode recusar. Use um trecho mais curto."
                }

                var asrc: MediaExporter.AudioSource?
                if let c = custom { asrc = .file(c) }
                else if wantsVideoAudio { asrc = .videoRange(url, start: start) }

                var mp4: URL?
                if let asrc {
                    busyText = "Misturando o áudio…"
                    mp4 = try await MediaExporter.makeMP4(frames: frames, fps: fps, audio: asrc,
                                                          duration: Double(frames.count) / Double(fps))
                }
                return Sticker(image: frames[0], webp: r.data, animated: true, audioURL: custom, videoURL: mp4)
            } catch {
                alertMessage = "Erro: \(error.localizedDescription)"
                return nil
            }
        }
    }
}
