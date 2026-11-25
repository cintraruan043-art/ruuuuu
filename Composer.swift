import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Parâmetros de edição
enum StickerFilter: String, CaseIterable, Identifiable {
    case none, mono, noir, sepia, chrome, fade, vivid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Normal"
        case .mono: return "P&B"
        case .noir: return "Noir"
        case .sepia: return "Vintage"
        case .chrome: return "Chrome"
        case .fade: return "Fade"
        case .vivid: return "Vívido"
        }
    }
}

struct EditParams: Equatable {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero          // fração do quadro (arraste)
    var quarterTurns = 0                // giros de 90°
    var flipH = false
    var fit = false                     // false = preencher, true = caber inteiro
    var brightness: Double = 0          // -0.5 ... 0.5
    var contrast: Double = 1            // 0.5 ... 1.5
    var saturation: Double = 1          // 0 ... 2
    var filter: StickerFilter = .none
    var corner: CGFloat = 0             // 0 = quadrado ... 1 = círculo
    var borderWidth: CGFloat = 0        // px
    var borderColor: Color = .white
    var text = ""
    var textColor: Color = .white
    var textSize: CGFloat = 56
    var textY: CGFloat = 0.82           // posição vertical (0...1)
}

// MARK: - Renderizador 512x512 (usado no preview, na foto e em cada quadro do vídeo)
enum StickerComposer {
    static let side: CGFloat = 512
    static let ciContext = CIContext()

    static func adjusted(_ cg: CGImage, _ p: EditParams) -> CGImage {
        let needs = p.brightness != 0 || p.contrast != 1 || p.saturation != 1 || p.filter != .none
        guard needs else { return cg }

        let base = CIImage(cgImage: cg)
        var ci = base
        func apply(_ f: CIFilter) {
            f.setValue(ci, forKey: kCIInputImageKey)
            if let o = f.outputImage { ci = o }
        }

        let cc = CIFilter.colorControls()
        cc.brightness = Float(p.brightness)
        cc.contrast = Float(p.contrast)
        cc.saturation = Float(p.saturation)
        apply(cc)

        switch p.filter {
        case .none: break
        case .mono: apply(CIFilter.photoEffectMono())
        case .noir: apply(CIFilter.photoEffectNoir())
        case .sepia: apply(CIFilter.sepiaTone())
        case .chrome: apply(CIFilter.photoEffectChrome())
        case .fade: apply(CIFilter.photoEffectFade())
        case .vivid:
            let v = CIFilter.vibrance()
            v.amount = 1.0
            apply(v)
        }
        return ciContext.createCGImage(ci, from: base.extent) ?? cg
    }

    static func render(_ src: UIImage, _ p: EditParams) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let canvas = CGSize(width: side, height: side)
        let rect = CGRect(origin: .zero, size: canvas)

        return UIGraphicsImageRenderer(size: canvas, format: fmt).image { ctx in
            let c = ctx.cgContext
            let radius = p.corner * side / 2
            let shape = UIBezierPath(roundedRect: rect, cornerRadius: radius)

            c.saveGState()
            shape.addClip()
            if let cg0 = src.cgImage {
                let img = UIImage(cgImage: adjusted(cg0, p))
                let turned = p.quarterTurns % 2 != 0
                let iw = turned ? img.size.height : img.size.width
                let ih = turned ? img.size.width : img.size.height
                let base = p.fit ? min(side / iw, side / ih) : max(side / iw, side / ih)
                let scale = base * p.zoom

                c.translateBy(x: side / 2 + p.offset.width * side,
                              y: side / 2 + p.offset.height * side)
                c.rotate(by: CGFloat(p.quarterTurns) * .pi / 2)
                if p.flipH { c.scaleBy(x: -1, y: 1) }
                c.scaleBy(x: scale, y: scale)
                img.draw(in: CGRect(x: -img.size.width / 2, y: -img.size.height / 2,
                                    width: img.size.width, height: img.size.height))
            }
            c.restoreGState()

            if p.borderWidth > 0 {
                let inset = p.borderWidth / 2
                let bp = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                      cornerRadius: max(0, radius - inset))
                bp.lineWidth = p.borderWidth
                UIColor(p.borderColor).setStroke()
                bp.stroke()
            }

            if !p.text.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: p.textSize, weight: .heavy),
                    .foregroundColor: UIColor(p.textColor),
                    .strokeColor: UIColor.black,
                    .strokeWidth: -5,
                    .paragraphStyle: style
                ]
                let str = p.text as NSString
                let width = side - 32
                let b = str.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin],
                                         attributes: attrs, context: nil)
                let h = ceil(b.height)
                let y = min(max(0, p.textY * side - h / 2), max(0, side - h))
                str.draw(with: CGRect(x: 16, y: y, width: width, height: h),
                         options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            }
        }
    }
}
