import SwiftUI

@main
struct FigmaCDPToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 6) {
                Text("Figma CDP Toolbar").font(.headline)
                Text(appDelegate.statusText).font(.caption)
                    .foregroundColor(appDelegate.isConnected ? .green : .red)
                if appDelegate.fonts.count > 0 {
                    Text("字体: \(appDelegate.fontLoadCount)/\(appDelegate.fonts.count)").font(FigmaTokens.fontCaption).foregroundColor(.primary)
                }
                Divider()
                if let node = appDelegate.selectedNode {
                    Text("\(node.type.rawValue) — \(node.name)").font(.caption)
                    if node.selectionCount > 1 {
                        Text("共 \(node.selectionCount) 个元素").font(.caption2).foregroundColor(.primary)
                    }
                }
                Divider()
                Button("重新连接") {
                    Task { await appDelegate.reconnect() }
                }
                Button("退出") { NSApplication.shared.terminate(nil) }
            }.padding().frame(width: 220)
        } label: {
            MenuBarLabel(delegate: appDelegate)
        }.menuBarExtraStyle(.menu)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        let name = delegate.isReconnecting ? "Refresh" : "Figma logo"
        if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let nsImage = loadSVG(url: url, size: 18) {
            Image(nsImage: nsImage)
        } else {
            Image(systemName: "paintpalette.fill")
        }
    }
}

private func loadSVG(url: URL, size: CGFloat) -> NSImage? {
    guard let nsImage = NSImage(contentsOf: url) else { return nil }
    nsImage.size = NSSize(width: size, height: size)
    nsImage.isTemplate = true
    return nsImage
}
