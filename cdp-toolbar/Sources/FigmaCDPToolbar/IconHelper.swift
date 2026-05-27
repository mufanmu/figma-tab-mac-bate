import SwiftUI

/// 加载 SVG 工具栏图标
func toolbarIcon(_ name: String, size: CGFloat = 32) -> Image {
    guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
          let nsImage = NSImage(contentsOf: url) else {
        return Image(systemName: "questionmark")
    }
    nsImage.size = NSSize(width: size, height: size)
    return Image(nsImage: nsImage)
}
