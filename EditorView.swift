import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import SDWebImageWebPCoder   // SPM: https://github.com/SDWebImage/SDWebImageWebPCoder

struct EditorView: View {
    @EnvironmentObject var store: Store
    @State private var item: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var current: UIImage?
    @State private var text = ""
    @State private var textColor = Color.white
    @State private var busy = false
    @StateObject private var audio = AudioManager()
    @State private var audioURL: URL?
    @State private var showImporter = false
    @State private var micDenied = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    PhotosPicker(selection: $item, matching: .images) {
                        label("Escolher foto", "photo.on.rectangle")
                    }
                    if current != nil {
                        HStack(spacing: 10) {
                            tool("Sem fundo", "person.crop.circle.badge.minus") { removeBG() }
                            tool("Original", "arrow.uturn.backward") { current = original }
                            tool("P&B", "circle.lefthalf.filled") { filter(CIFilter.photoEffectMono()) }
                            tool("Vintage", "camera.filters") { filter(CIFilter.sepiaTone()) }
                        }
                        HStack {
                            TextField("Texto na figurinha", text: $text)
                                .padding(10).background(Theme.card).cornerRadius(12)
                            ColorPicker("", selection: $textColor).labelsHidden()
                        }
                        audioSection
                        Button { addToPack() } label: { label("Adicionar ao pacote", "plus.circle.fill") }
                    }
                }.padding()
            }
        }
        .onChange(of: item) { _, new in load(new) }
        .onAppear { audio.onRecorded = { audioURL = $0 } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let u) = result, let c = audio.importFile(u) { audioURL = c }
        }
    }

    var audioSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                tool(audio.isRecording ? "Parar" : "Gravar voz",
                     audio.isRecording ? "stop.circle.fill" : "mic.fill") {
                    if audio.isRecording { audio.stopRecording() }
                    else { Task { micDenied = !(await audio.startRecording()) } }
                }
                tool("Arquivo", "waveform") { showImporter = true }
                if let url = audioURL {
                    tool(audio.isPlaying ? "Parar" : "Ouvir",
                         audio.isPlaying ? "speaker.slash.fill" : "play.fill") {
                        if audio.isPlaying { audio.stop() } else { audio.play(url) }
                    }
                    tool("Remover", "trash") { audio.stop(); audioURL = nil }
                }
            }
            if micDenied {
                Text("Permita o microfone em Ajustes para gravar.")
                    .font(.footnote).foregroundColor(.orange)
            }
            if audioURL != nil {
                Text("🔊 Áudio anexado (máx. 10 s)").font(.footnote).foregroundColor(Theme.soft)
            }
        }
    }

    var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(Theme.card)
            if busy { ProgressView() }
            else if let img = render() {
                Image(uiImage: img).resizable().scaledToFit().padding(12)
            } else {
                Text("Envie uma foto para criar\nsua figurinha ✨")
                    .multilineTextAlignment(.center).foregroundColor(Theme.soft)
            }
        }.frame(height: 340)
    }

    func label(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).fontWeight(.semibold).foregroundColor(Theme.bg)
            .frame(maxWidth: .infinity).padding().background(Theme.accent).cornerRadius(16)
    }

    func tool(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack { Image(systemName: icon).font(.title3); Text(t).font(.caption2) }
                .foregroundColor(Theme.soft).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Theme.card).cornerRadius(14)
        }
    }

    func load(_ i: PhotosPickerItem?) {
        Task {
            guard let d = try? await i?.loadTransferable(type: Data.self),
                  let img = UIImage(data: d) else { return }
            let n = img.normalized(); original = n; current = n
        }
    }

    func removeBG() {
        guard let img = current, let cg = img.cgImage else { return }
        busy = true
        DispatchQueue.global().async {
            let req = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            var out: UIImage?
            if (try? handler.perform([req])) != nil, let r = req.results?.first,
               let buf = try? r.generateMaskedImage(ofInstances: r.allInstances, from: handler, croppedToInstancesExtent: true) {
                let ci = CIImage(cvPixelBuffer: buf)
                if let c = CIContext().createCGImage(ci, from: ci.extent) { out = UIImage(cgImage: c) }
            }
            DispatchQueue.main.async { if let out { current = out }; busy = false }
        }
    }

    func filter(_ f: CIFilter) {
        guard let img = current, let ci = CIImage(image: img) else { return }
        f.setValue(ci, forKey: kCIInputImageKey)
        if let o = f.outputImage, let cg = CIContext().createCGImage(o, from: o.extent) {
            current = UIImage(cgImage: cg)
        }
    }

    /// Renderiza 512x512 transparente com a imagem centralizada + texto
    func render() -> UIImage? {
        guard let img = current else { return nil }
        let size = CGSize(width: 512, height: 512)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            let r = min(size.width / img.size.width, size.height / img.size.height)
            let w = img.size.width * r, h = img.size.height * r
            img.draw(in: CGRect(x: (512 - w) / 2, y: (512 - h) / 2, width: w, height: h))
            if !text.isEmpty {
                let p = NSMutableParagraphStyle(); p.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 56, weight: .heavy),
                    .foregroundColor: UIColor(textColor),
                    .strokeColor: UIColor.black, .strokeWidth: -4, .paragraphStyle: p]
                (text as NSString).draw(in: CGRect(x: 10, y: 400, width: 492, height: 100), withAttributes: attrs)
            }
        }
    }

    func addToPack() {
        if let r = render() {
            store.stickers.append(Sticker(image: r, audioURL: audioURL))
            text = ""; audioURL = nil; audio.stop()
        }
    }
}

