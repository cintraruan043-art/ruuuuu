import SwiftUI
import PhotosUI
import Vision
import CoreImage.CIFilterBuiltins
import SDWebImageWebPCoder   // SPM: https://github.com/SDWebImage/SDWebImageWebPCoder

enum Theme {
    static let bg = Color(red: 0.06, green: 0.08, blue: 0.14)
    static let card = Color(red: 0.11, green: 0.14, blue: 0.24)
    static let accent = Color(red: 0.55, green: 0.72, blue: 0.95)
    static let soft = Color(red: 0.70, green: 0.80, blue: 0.95)
}

struct Sticker: Identifiable {
    let id = UUID()
    var image: UIImage
    var emoji = "😀"
    var audioURL: URL? = nil
}


extension UIImage {
    /// Corrige a rotação de fotos tiradas no iPhone
    func normalized() -> UIImage {
        if imageOrientation == .up { return self }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
