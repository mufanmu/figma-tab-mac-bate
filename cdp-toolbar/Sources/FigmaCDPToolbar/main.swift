import SwiftUI

@main
struct FigmaCDPToolbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Figma CDP", systemImage: "paintpalette.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Figma CDP Toolbar").font(.headline)
                Text(appDelegate.statusText)
                    .font(.caption)
                    .foregroundColor(appDelegate.isConnected ? .green : .red)
                Divider()
                if let node = appDelegate.selectedNode {
                    Text("选中: \(node.type.rawValue) - \(node.name)").font(.caption)
                    if node.selectionCount > 1 {
                        Text("共 \(node.selectionCount) 个元素").font(.caption2).foregroundColor(.secondary)
                    }
                } else {
                    Text(appDelegate.isConnected ? "请在 Figma 中选中元素" : "等待连接...")
                        .font(.caption).foregroundColor(.secondary)
                }
                Divider()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .padding().frame(width: 220)
        }
        .menuBarExtraStyle(.menu)
    }
}
