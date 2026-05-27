import SwiftUI

// MARK: - Figma Design System (from DESIGN.md)
// 基于 Figma 官方营销设计系统，黑白主色调 + pastel color-block 规范

enum FigmaColors {
    /// 纯黑 — 所有文字、主要 CTA 的主色
    static let ink = Color(hex: "000000")
    /// 纯白 — 默认画布背景
    static let canvas = Color(hex: "FFFFFF")
    /// 次要表面 — 输入框背景、图标按钮背景
    static let surfaceSoft = Color(hex: "F7F7F5")
    /// 分割线 / 边框 — 1px hairline
    static let hairline = Color(hex: "E6E6E6")
    /// 更细的分割线 — 表格行分隔等
    static let hairlineSoft = Color(hex: "F1F1F1")
    /// 阴影 — 极浅，Figma 是 shadow-light 设计
    static let shadow = Color.black.opacity(0.06)
    /// 覆盖层 scrim (黑 ~60% opacity)
    static let overlayScrim = Color.black.opacity(0.6)
    /// Figma 产品 UI 蓝色 — 选中项标识
    static let accentBlue = Color(hex: "0D99FF")
}

enum FigmaTokens {
    // MARK: - 尺寸
    static let toolbarHeight: CGFloat = 44
    static let controlHeight: CGFloat = 32
    static let iconButtonSize: CGFloat = 32
    static let toggleButtonSize: CGFloat = 32

    // MARK: - 圆角 (DESIGN.md rounded 规范)
    /// 小控件、chip
    static let roundedSm: CGFloat = 6
    /// 容器、输入框、toolbar 整体
    static let roundedMd: CGFloat = 8
    /// 大容器、卡片
    static let roundedLg: CGFloat = 24
    /// 药丸按钮
    static let roundedPill: CGFloat = 50
    /// 圆形
    static let roundedFull: CGFloat = 9999

    // MARK: - 间距 (8px base unit)
    static let spacingXXS: CGFloat = 4
    static let spacingXS: CGFloat = 8
    static let spacingSM: CGFloat = 12

    // MARK: - 字体
    /// figmaMono caption — 标签、数值（10px, monospaced）
    static let fontCaption = Font.system(size: 10, weight: .regular, design: .monospaced)
    /// figmaMono small — 更小的标注（8px, monospaced）
    static let fontCaptionSmall = Font.system(size: 8, weight: .regular, design: .monospaced)
    /// figmaSans body — 默认正文（11px, weight 330）
    static let fontBody = Font.system(size: 11, weight: .regular)
    /// figmaSans body medium — 强调正文（11px, weight 480）
    static let fontBodyMedium = Font.system(size: 11, weight: .medium)
    /// figmaSans body small — 较小的正文（10px）
    static let fontBodySmall = Font.system(size: 10, weight: .regular)
    /// 图标尺寸
    static let iconSize: CGFloat = 10
    static let iconSizeSmall: CGFloat = 8
}

// MARK: - Figma Theme (light / dark)

struct FigmaTheme {
    let ink: Color
    let canvas: Color
    let surfaceSoft: Color
    let hairline: Color
    let hairlineSoft: Color
    let shadow: Color

    /// 浅色主题 — Figma 营销站点设计规范
    static let light = FigmaTheme(
        ink: Color(hex: "000000"),
        canvas: Color(hex: "FFFFFF"),
        surfaceSoft: Color(hex: "F7F7F5"),
        hairline: Color(hex: "E6E6E6"),
        hairlineSoft: Color(hex: "F1F1F1"),
        shadow: Color.black.opacity(0.06)
    )

    /// 暗色主题 — Figma 编辑器面板暗色风格
    static let dark = FigmaTheme(
        ink: Color(hex: "FFFFFF"),
        canvas: Color(hex: "2C2C2C"),
        surfaceSoft: Color(hex: "383838"),
        hairline: Color(hex: "505050"),
        hairlineSoft: Color(hex: "444444"),
        shadow: Color.black.opacity(0.25)
    )
}

// MARK: - Color Hex 扩展

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
