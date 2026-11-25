import SwiftUI
import UIKit

// MARK: - Helpers de cor
extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count != 6 { s = "808080" }
        var v: UInt64 = 0
        _ = Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }

    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount,
                       green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount,
                       alpha: 1)
    }
}

extension UIImage {
    /// Corrige rotação (fotos do iPhone) e reduz para no máximo `maxSide` px.
    func normalized(maxSide: CGFloat = 1280) -> UIImage {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return self }
        let scale = min(1, maxSide / max(w, h))
        if imageOrientation == .up && scale == 1 { return self }
        let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: target, format: f).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Tema do app (claro / escuro / cores personalizadas)
final class AppTheme: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Automático"
            case .light: return "Claro"
            case .dark: return "Escuro"
            }
        }
    }

    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "accentHex") }
    }
    /// nil = usa o fundo padrão do tema
    @Published var bgHex: String? {
        didSet {
            if let v = bgHex { UserDefaults.standard.set(v, forKey: "bgHex") }
            else { UserDefaults.standard.removeObject(forKey: "bgHex") }
        }
    }

    init() {
        let d = UserDefaults.standard
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        accentHex = d.string(forKey: "accentHex") ?? "8CB8F2"
        bgHex = d.string(forKey: "bgHex")
    }

    private func dyn(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private var customBg: UIColor? { bgHex.map { UIColor(hex: $0) } }

    /// Esquema forçado (se o fundo for personalizado, segue a luminosidade dele)
    var scheme: ColorScheme? {
        if let c = customBg { return c.luminance < 0.5 ? .dark : .light }
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var accentUI: UIColor { UIColor(hex: accentHex) }
    var accent: Color { Color(uiColor: accentUI) }
    var onAccent: Color { accentUI.luminance > 0.6 ? Color.black : Color.white }

    var bg: Color {
        if let c = customBg { return Color(uiColor: c) }
        return dyn(UIColor(hex: "F2F4FA"), UIColor(hex: "0F1424"))
    }

    var card: Color {
        if let c = customBg {
            let m = c.luminance < 0.5 ? c.mixed(with: .white, amount: 0.10) : c.mixed(with: .black, amount: 0.06)
            return Color(uiColor: m)
        }
        return dyn(UIColor.white, UIColor(hex: "1C2340"))
    }

    var text: Color {
        if let c = customBg { return c.luminance < 0.5 ? Color.white : Color(uiColor: UIColor(hex: "10131F")) }
        return dyn(UIColor(hex: "10131F"), UIColor.white)
    }

    var soft: Color { text.opacity(0.62) }
}

// MARK: - Componentes visuais reutilizáveis
struct Card<Content: View>: View {
    @EnvironmentObject var theme: AppTheme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .foregroundColor(theme.text)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PrimaryButton: View {
    @EnvironmentObject var theme: AppTheme
    let title: String
    let icon: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(theme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? theme.accent : Color.gray.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!enabled)
    }
}

struct SmallTool: View {
    @EnvironmentObject var theme: AppTheme
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void
    init(_ title: String, _ icon: String, active: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.active = active; self.action = action
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(active ? theme.onAccent : theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? theme.accent : theme.accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct Chip: View {
    @EnvironmentObject var theme: AppTheme
    let title: String
    let icon: String?
    let selected: Bool
    let action: () -> Void
    init(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.selected = selected; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(selected ? theme.onAccent : theme.text)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? theme.accent : theme.card, in: Capsule())
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 14
            let rows = Int(ceil(size.height / s))
            let cols = Int(ceil(size.width / s))
            for row in 0..<rows {
                for col in 0..<cols {
                    let dark = (row + col) % 2 == 0
                    let r = CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s)
                    ctx.fill(Path(r), with: .color(Color.gray.opacity(dark ? 0.28 : 0.12)))
                }
            }
        }
    }
}
