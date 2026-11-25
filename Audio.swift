import SwiftUI
import AVFoundation
import UIKit
import SDWebImageWebPCoder

// MARK: - Gravação, importação e reprodução de áudio (máx. 10 s)
@MainActor
final class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    static let maxDuration: TimeInterval = 10
    @Published var isRecording = false
    @Published var isPlaying = false
    var onRecorded: ((URL) -> Void)?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func startRecording() async -> Bool {
        stop()
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return false }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        r.delegate = self
        recorder = r
        r.record(forDuration: Self.maxDuration)   // para sozinho em 10 s
        isRecording = true
        return true
    }

    func stopRecording() { recorder?.stop() }

    nonisolated func audioRecorderDidFinishRecording(_ r: AVAudioRecorder, successfully ok: Bool) {
        let url = r.url
        Task { @MainActor in
            self.isRecording = false
            if ok { self.onRecorded?(url) }
        }
    }

    func importFile(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("imp-\(UUID().uuidString).\(ext)")
        do { try FileManager.default.copyItem(at: url, to: dest); return dest } catch { return nil }
    }

    func play(_ url: URL) {
        stop()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        player = p
        p.play()
        isPlaying = true
        stopTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.maxDuration * 1_000_000_000))
            if !Task.isCancelled { stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop(); player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

// MARK: - Erros
struct MediaError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - WebP, quadros de vídeo e MP4 com áudio
enum MediaExporter {
    enum AudioSource {
        case file(URL)
        case videoRange(URL, start: Double)
    }

    static var tmp: URL { FileManager.default.temporaryDirectory }

    // ---------- WebP ----------
    private static func encode(_ img: UIImage, _ q: Double) -> Data? {
        SDImageWebPCoder.shared.encodedData(with: img, format: .webP,
                                            options: [.encodeCompressionQuality: q])
    }

    /// Figurinha estática: máx. 100 KB
    static func webpStatic(_ img: UIImage, maxBytes: Int = 100_000) -> Data? {
        var q = 0.85
        var data = encode(img, q)
        while let d = data, d.count > maxBytes, q > 0.1 {
            q -= 0.1
            data = encode(img, q)
        }
        return data
    }

    /// Figurinha animada: máx. 500 KB (reduz qualidade e depois quadros até caber)
    static func webpAnimated(frames: [UIImage], fps: Int, maxBytes: Int = 500_000) -> (data: Data, fits: Bool)? {
        guard frames.count >= 2 else { return nil }
        let total = Double(frames.count) / Double(fps)
        let attempts: [(step: Int, q: Double)] = [
            (1, 0.6), (1, 0.45), (1, 0.3), (2, 0.45), (2, 0.3), (2, 0.15), (3, 0.15)
        ]
        var best: Data?
        for a in attempts {
            if Task.isCancelled { break }
            let sub = stride(from: 0, to: frames.count, by: a.step).map { frames[$0] }
            guard sub.count >= 2,
                  let anim = UIImage.animatedImage(with: sub, duration: total),
                  let data = encode(anim, a.q) else { continue }
            if best == nil || data.count < (best?.count ?? Int.max) { best = data }
            if data.count <= maxBytes { return (data, true) }
        }
        if let b = best { return (b, false) }
        return nil
    }

    // ---------- Vídeo -> quadros 512x512 já editados ----------
    static func renderVideoFrames(url: URL, start: Double, length: Double, fps: Int,
                                  params: EditParams,
                                  progress: @escaping @Sendable (Double) -> Void) async throws -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1024, height: 1024)
        let tol = CMTime(seconds: 0.04, preferredTimescale: 600)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter = tol

        let n = max(2, Int((length * Double(fps)).rounded()))
        var frames: [UIImage] = []
        frames.reserveCapacity(n)
        for i in 0..<n {
            try Task.checkCancellation()
            let t = CMTime(seconds: start + Double(i) / Double(fps), preferredTimescale: 600)
            let result = try await gen.image(at: t)
            frames.append(StickerComposer.render(UIImage(cgImage: result.image), params))
            progress(Double(i + 1) / Double(n))
        }
        return frames
    }

    // ---------- MP4 ----------
    static func duration(of url: URL) async -> Double {
        let d = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        return d.isFinite ? d : 0
    }

    static func makeMP4(frames: [UIImage], fps: Int, audio: AudioSource?, duration: Double) async throws -> URL {
        let silent = try await makeSilentVideo(frames: frames, fps: Int32(fps))
        guard let audio else { return silent }
        return try await addAudio(to: silent, source: audio, duration: duration)
    }

    private static func makeSilentVideo(frames: [UIImage], fps: Int32) async throws -> URL {
        let url = tmp.appendingPathComponent("v-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 512, AVVideoHeightKey: 512])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 512, kCVPixelBufferHeightKey as String: 512])
        guard writer.canAdd(input) else { throw MediaError("Não consegui preparar o vídeo.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw MediaError(writer.error?.localizedDescription ?? "Não consegui iniciar o vídeo.")
        }
        writer.startSession(atSourceTime: .zero)

        var lastImage: UIImage?
        var lastBuffer: CVPixelBuffer?
        for (i, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            let buf: CVPixelBuffer
            if let li = lastImage, li === frame, let lb = lastBuffer {
                buf = lb
            } else {
                guard let nb = pixelBuffer(from: frame) else { throw MediaError("Falha ao montar o quadro do vídeo.") }
                buf = nb; lastImage = frame; lastBuffer = nb
            }
            adaptor.append(buf, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(frames.count), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw MediaError(writer.error?.localizedDescription ?? "Falha ao gravar o vídeo.")
        }
        return url
    }

    private static func addAudio(to videoURL: URL, source: AudioSource, duration: Double) async throws -> URL {
        let vAsset = AVURLAsset(url: videoURL)
        guard let vSrc = try await vAsset.loadTracks(withMediaType: .video).first else {
            throw MediaError("Vídeo sem trilha de imagem.")
        }
        let comp = AVMutableComposition()
        guard let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaError("Falha ao montar o vídeo.")
        }
        let vDur = try await vAsset.load(.duration)
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vSrc, at: .zero)

        let aURL: URL
        let aStart: Double
        switch source {
        case .file(let u): aURL = u; aStart = 0
        case .videoRange(let u, let s): aURL = u; aStart = s
        }
        let aAsset = AVURLAsset(url: aURL)
        if let aSrc = try await aAsset.loadTracks(withMediaType: .audio).first,
           let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let aDur = try await aAsset.load(.duration).seconds
            let len = max(0, min(duration, aDur - aStart))
            if len > 0.05 {
                let range = CMTimeRange(start: CMTime(seconds: aStart, preferredTimescale: 600),
                                        duration: CMTime(seconds: len, preferredTimescale: 600))
                try a.insertTimeRange(range, of: aSrc, at: .zero)
            }
        }

        let out = tmp.appendingPathComponent("figurinha-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaError("Não consegui exportar o vídeo com som.")
        }
        session.outputURL = out
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            throw MediaError(session.error?.localizedDescription ?? "Falha ao exportar o vídeo com som.")
        }
        return out
    }

    private static func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 512, 512, kCVPixelFormatType_32BGRA, attrs, &pb)
        guard status == kCVReturnSuccess, let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: 512, height: 512,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        return buf
    }
}

// MARK: - Compartilhar arquivo
struct ShareItem: Identifiable { let id = UUID(); let url: URL }

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
