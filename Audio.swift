import SwiftUI
import AVFoundation
import UIKit

// MARK: - Gravação, importação e reprodução (máx. 10 s)
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
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("imp-\(UUID().uuidString).\(url.pathExtension)")
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

// MARK: - Exporta figurinha + áudio como vídeo .mp4 (para usar no criador do WhatsApp)
enum ExportError: Error { case failed }

enum StickerVideoExporter {
    static var tmp: URL { FileManager.default.temporaryDirectory }

    static func export(image: UIImage, audio: URL) async throws -> URL {
        let aAsset = AVURLAsset(url: audio)
        let full = try await aAsset.load(.duration).seconds
        let dur = max(1, min(full, AudioManager.maxDuration))
        let videoURL = try await makeVideo(image: image, seconds: dur + 0.5)

        let vAsset = AVURLAsset(url: videoURL)
        guard let vSrc = try await vAsset.loadTracks(withMediaType: .video).first,
              let aSrc = try await aAsset.loadTracks(withMediaType: .audio).first
        else { throw ExportError.failed }
        let comp = AVMutableComposition()
        guard let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.failed }
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: dur, preferredTimescale: 600))
        try v.insertTimeRange(range, of: vSrc, at: .zero)
        try a.insertTimeRange(range, of: aSrc, at: .zero)

        let out = tmp.appendingPathComponent("figurinha-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.failed }
        session.outputURL = out
        session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else { throw ExportError.failed }
        return out
    }

    static func makeVideo(image: UIImage, seconds: Double) async throws -> URL {
        let url = tmp.appendingPathComponent("v-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 512, AVVideoHeightKey: 512])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 512, kCVPixelBufferHeightKey as String: 512])
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.failed }
        writer.startSession(atSourceTime: .zero)
        guard let buffer = pixelBuffer(from: image) else { throw ExportError.failed }
        let fps: Int32 = 10
        let frames = Int(seconds * Double(fps))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.failed }
        return url
    }

    static func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cg = image.cgImage else { return nil }
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 512, 512, kCVPixelFormatType_32ARGB, attrs, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: 512, height: 512,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.setFillColor(UIColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1).cgColor)
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
