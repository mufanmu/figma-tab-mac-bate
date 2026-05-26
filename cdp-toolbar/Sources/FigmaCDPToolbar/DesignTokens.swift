import SwiftUI

enum FigmaColors {
    static let bg = Color(hex: "FFFFFF")
    static let bgSecondary = Color(hex: "F5F5F5")
    static let bgTertiary = Color(hex: "E6E6E6")
    static let border = Color(hex: "E5E5E5")
    static let textPrimary = Color(hex: "1E1E1E")
    static let textSecondary = Color(hex: "757575")
    static let accent = Color(hex: "0D99FF")
    static let accentHover = Color(hex: "0B8AE6")
    static let dangerous = Color(hex: "F24822")
    static let shadow = Color.black.opacity(0.1)
}

enum FigmaTokens {
    static let toolbarHeight: CGFloat = 40
    static let controlHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 8
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let fontMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let fontBody = Font.system(size: 12, weight: .regular)
    static let fontBodyMedium = Font.system(size: 12, weight: .medium)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }

    func toRGBA() -> RGBA? {
        guard let cgColor = NSColor(self).usingColorSpace(.deviceRGB)?.cgColor,
              let components = cgColor.components, components.count >= 3 else {
            return nil
        }
        return RGBA(r: components[0], g: components[1], b: components[2], a: cgColor.alpha)
    }
}
