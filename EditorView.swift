import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: AppTheme
    @StateObject private var model = EditorModel()
    @StateObject private var audio = AudioManager()

    @State private var item: PhotosPickerItem?
    @State private var tool: Tool = .adjust
    @State private var showImporter = false
    @State private var micDenied = false
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var toast: String?

    enum Tool: String, Identifiable {
        case adjust, trim, filters, text, sound
        var id: String { rawValue }
        var title: String {
            switch self {
            case .adjust: return "Ajustar"
            case .trim: return "Cortar vídeo"
            case .filters: return "Filtros"
            case .text: return "Texto"
            case .sound: return "Som"
            }
        }
        var icon: String {
            switch self {
            case .adjust: return "crop.rotate"
            case .trim: return "scissors"
            case .filters: return "camera.filters"
            case .text: return "textformat"
            case .sound: return "waveform"
            }
        }
    }

    var tools: [Tool] {
        model.kind == .video ? [.adjust, .trim, .filters, .text, .sound]
                             : [.adjust, .filters, .text, .sound]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        preview
                        sourceBar
                        if model.kind != .none {
                            toolPicker
                            Card { toolPanel }
                            PrimaryButton(title: "Adicionar ao pacote", icon: "plus.circle.fill") {
                                Task { await add() }
                            }
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Criar figurinha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Limpar") { audio.stop(); model.reset() }
                        .disabled(model.kind == .none)
                }
            }
        }
        .overlay { busyOverlay }
        .overlay(alignment: .bottom) { toastView }
        .alert("Aviso", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                audio.stop()
                await model.load(new)
                item = nil
            }
        }
        .onChange(of: model.kind) { _, _ in tool = .adjust }
        .onChange(of: model.trimStart) { _, _ in
            model.clampTrim(); model.scheduleThumb()
        }
        .onChange(of: model.trimLength) { _, _ in model.scheduleThumb() }
        .onChange(of: model.previewFrac) { _, _ in model.scheduleThumb() }
        .onAppear { audio.onRecorded = { url in model.audioURL = url } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let u) = result, let c = audio.importFile(u) { model.audioURL = c }
        }
    }

    // MARK: Preview com arrastar e pinça
    var preview: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - 20)
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.card)
                if let src = model.source {
                    Checkerboard()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(10)
                    Image(uiImage: StickerComposer.render(src, model.params))
                        .resizable().scaledToFit().padding(10)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.largeTitle).foregroundColor(theme.accent)
                        Text("Escolha uma foto ou um vídeo\npara criar sua figurinha")
                            .multilineTextAlignment(.center)
                            .foregroundColor(theme.soft)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(panAndZoom(w), including: model.source == nil ? .none : .all)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    func panAndZoom(_ w: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if dragStart == nil { dragStart = model.params.offset }
                let base = dragStart ?? .zero
                model.params.offset = CGSize(width: base.width + v.translation.width / w,
                                             height: base.height + v.translation.height / w)
            }
            .onEnded { _ in dragStart = nil }
            .simultaneously(with:
                MagnifyGesture()
                    .onChanged { v in
                        if zoomStart == nil { zoomStart = model.params.zoom }
                        model.params.zoom = min(max((zoomStart ?? 1) * v.magnification, 0.3), 5)
                    }
                    .onEnded { _ in zoomStart = nil }
            )
    }

    var sourceBar: some View {
        PhotosPicker(selection: $item, matching: .any(of: [.images, .videos])) {
            Label(model.kind == .none ? "Escolher foto ou vídeo" : "Trocar mídia",
                  systemImage: "photo.on.rectangle.angled")
                .font(.headline)
                .foregroundColor(model.kind == .none ? theme.onAccent : theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(model.kind == .none ? theme.accent : theme.card,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    var toolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tools) { t in
                    Chip(t.title, icon: t.icon, selected: tool == t) { tool = t }
                }
            }
        }
    }

    // MARK: Painéis
    @ViewBuilder var toolPanel: some View {
        switch tool {
        case .adjust: adjustPanel
        case .trim: trimPanel
        case .filters: filtersPanel
        case .text: textPanel
        case .sound: soundPanel
        }
    }

    var adjustPanel: some View {
        VStack(spacing: 12) {
            sliderRow("Zoom", $model.params.zoom, 0.3...5,
                      String(format: "%.1fx", Double(model.params.zoom)))
            HStack(spacing: 8) {
                SmallTool("Girar", "rotate.right") {
                    model.params.quarterTurns = (model.params.quarterTurns + 1) % 4
                }
                SmallTool("Espelhar", "arrow.left.and.right") { model.params.flipH.toggle() }
                SmallTool("Centralizar", "scope") {
                    model.params.offset = .zero
                    model.params.zoom = 1
                }
                SmallTool(model.params.fit ? "Preencher" : "Caber",
                          model.params.fit ? "arrow.up.left.and.arrow.down.right"
                                           : "arrow.down.right.and.arrow.up.left") {
                    model.params.fit.toggle()
                }
            }
            if model.kind == .photo {
                HStack(spacing: 8) {
                    SmallTool("Sem fundo", "person.crop.circle.badge.minus") { model.removeBackground() }
                    SmallTool("Original", "arrow.uturn.backward") { model.resetImage() }
                }
            }
            sliderRow("Forma (quadrado → círculo)", $model.params.corner, 0...1,
                      "\(Int(model.params.corner * 100))%")
            sliderRow("Borda", $model.params.borderWidth, 0...30,
                      "\(Int(model.params.borderWidth)) px")
            if model.params.borderWidth > 0 {
                ColorPicker("Cor da borda", selection: $model.params.borderColor, supportsOpacity: false)
            }
            Text("Dica: arraste a prévia para mover e use dois dedos para dar zoom.")
                .font(.caption).foregroundColor(theme.soft)
        }
    }

    var trimPanel: some View {
        VStack(spacing: 12) {
            sliderRow("Início", $model.trimStart, 0...max(model.duration - 0.5, 0.5),
                      timeString(model.trimStart))
            sliderRow("Duração", $model.trimLength,
                      0.5...max(0.5, min(EditorModel.maxClip, model.duration - model.trimStart)),
                      timeString(model.trimLength))
            sliderRow("Ver quadro do trecho", $model.previewFrac, 0...1, "")
            Text("Vídeo original: \(timeString(model.duration)). A figurinha tem no máximo \(Int(EditorModel.maxClip)) s (limite do som no WhatsApp e do tamanho do arquivo).")
                .font(.caption).foregroundColor(theme.soft)
        }
    }

    var filtersPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StickerFilter.allCases) { f in
                        Chip(f.title, selected: model.params.filter == f) { model.params.filter = f }
                    }
                }
            }
            sliderRow("Brilho", $model.params.brightness, -0.5...0.5,
                      String(format: "%+.2f", model.params.brightness))
            sliderRow("Contraste", $model.params.contrast, 0.5...1.5,
                      String(format: "%.2f", model.params.contrast))
            sliderRow("Saturação", $model.params.saturation, 0...2,
                      String(format: "%.2f", model.params.saturation))
            SmallTool("Zerar cores", "arrow.counterclockwise") {
                model.params.brightness = 0
                model.params.contrast = 1
                model.params.saturation = 1
                model.params.filter = .none
            }
        }
    }

    var textPanel: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Texto na figurinha", text: $model.params.text)
                    .padding(10)
                    .background(theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                ColorPicker("", selection: $model.params.textColor, supportsOpacity: false).labelsHidden()
            }
            sliderRow("Tamanho", $model.params.textSize, 24...120, "\(Int(model.params.textSize))")
            sliderRow("Posição (cima → baixo)", $model.params.textY, 0.08...0.95,
                      "\(Int(model.params.textY * 100))%")
        }
    }

    var soundPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                SmallTool(audio.isRecording ? "Parar" : "Gravar voz",
                          audio.isRecording ? "stop.circle.fill" : "mic.fill",
                          active: audio.isRecording) {
                    if audio.isRecording { audio.stopRecording() }
                    else { Task { micDenied = !(await audio.startRecording()) } }
                }
                SmallTool("Arquivo", "folder") { showImporter = true }
                if let url = model.audioURL {
                    SmallTool(audio.isPlaying ? "Parar" : "Ouvir",
                              audio.isPlaying ? "speaker.slash.fill" : "play.fill") {
                        if audio.isPlaying { audio.stop() } else { audio.play(url) }
                    }
                    SmallTool("Remover", "trash") { audio.stop(); model.audioURL = nil }
                }
            }
            if micDenied {
                Text("Permita o microfone em Ajustes para gravar.")
                    .font(.footnote).foregroundColor(.orange)
            }
            if model.kind == .video && model.hasVideoAudio {
                Toggle("Usar o som original do vídeo", isOn: $model.useVideoAudio)
                    .tint(theme.accent)
                    .disabled(model.audioURL != nil)
                if model.audioURL != nil {
                    Text("O áudio gravado/importado substitui o som do vídeo.")
                        .font(.caption).foregroundColor(theme.soft)
                }
            }
            if model.audioURL != nil || (model.kind == .video && model.hasVideoAudio && model.useVideoAudio) {
                Text("🔊 A figurinha vai com som (máx. \(model.kind == .video ? Int(EditorModel.maxClip) : Int(AudioManager.maxDuration)) s).")
                    .font(.footnote).foregroundColor(theme.soft)
            }
            Text("O som fica guardado junto da figurinha. Na aba Pacote você gera o vídeo com som para criar a figurinha de som no próprio WhatsApp.")
                .font(.caption).foregroundColor(theme.soft)
        }
    }

    // MARK: Auxiliares
    private func sliderRow<V: BinaryFloatingPoint>(_ title: String, _ value: Binding<V>,
                                                   _ range: ClosedRange<V>, _ shown: String) -> some View
    where V.Stride: BinaryFloatingPoint {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(shown).font(.caption).foregroundColor(theme.soft)
            }
            Slider(value: value, in: range).tint(theme.accent)
        }
    }

    private func timeString(_ t: Double) -> String { String(format: "%.1f s", t) }

    private func add() async {
        audio.stop()
        if let s = await model.buildSticker() {
            store.add(s)
            withAnimation { toast = "Adicionada ao pacote ✓" }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }

    @ViewBuilder var busyOverlay: some View {
        if model.busy {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(model.busyText).font(.subheadline.weight(.semibold))
                    if model.progress > 0 && model.progress < 1 {
                        ProgressView(value: model.progress).frame(width: 170).tint(theme.accent)
                    }
                }
                .foregroundColor(theme.text)
                .padding(22)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    @ViewBuilder var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(theme.accent, in: Capsule())
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
