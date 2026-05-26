# Figma CDP Toolbar

macOS 原生浮动工具栏，通过 Chrome DevTools Protocol 直接与 Figma 桌面端通信，**无需 Figma 插件**即可实时读取/修改选中元素属性。工具栏始终跟随选中元素，支持缩放和平移。

## 架构

```
Figma Desktop (hex-patched app.asar)
    ↕ WebSocket CDP (localhost:9222)
SwiftUI NSPanel (cdp-toolbar)
    ↕ Runtime.evaluate("figma.*")
Figma Editor JS Context
```

## 功能

- **无需插件** — 通过 CDP 直接访问 `figma.*` API，读写元素属性
- **形状属性编辑** — 填充色（ColorPicker）、圆角、不透明度
- **文字属性编辑** — 字号（异步 loadFontAsync）
- **元素跟随** — 工具栏固定在选中元素上方 20px，缩放平移时始终跟随
- **智能定位** — 放大到极限时自动切到下方（画布 2/3 处），不超出视野
- **多选支持** — 显示选中数量（+N）
- **8ms 实时轮询** — viewport.bounds 精确坐标映射，120fps 丝滑定位
- **Borderless NSPanel** — 无焦点抢夺，浮动于 Figma 之上

## 使用

```bash
# 1. 启动 Figma（必须先 hex-patch app.asar）
open -a "Figma+EX" --args '--remote-debugging-port=9222' '--remote-allow-origins=*'

# 2. 构建并运行工具栏
cd cdp-toolbar && swift build && .build/debug/FigmaCDPToolbar &
```

### 准备工作：hex-patch Figma

Figma 生产版本主动调用了 `app.commandLine.removeSwitch("remote-debugging-port")` 来禁止 CDP。需要 hex-patch `app.asar`，将 `removeSwitch` 替换为 `hasSwitch`：

```bash
# 在 asar 中找到并替换（12 字节原样替换）
# removeSwitch → hasSwitch（+3个空格对齐）
```

参考 `demo/` 目录中的诊断脚本。

## 技术细节

| 组件 | 文件 |
|------|------|
| CDP WebSocket 通信 | `CDPClient.swift` |
| Figma API 封装 | `FigmaAPI.swift` |
| NSPanel + 定位 + 轮询 | `AppDelegate.swift` |
| 工具栏 UI | `ToolbarView.swift` |
| 坐标定位 | `viewport.bounds` 线性映射 canvas→DOM→Cocoa |
| CDP 通道 | `Runtime.evaluate` → `result.result.value`（双层嵌套） |

## 项目结构

```
├── cdp-toolbar/           # Swift 工具栏
│   ├── Package.swift
│   └── Sources/FigmaCDPToolbar/
│       ├── main.swift
│       ├── AppDelegate.swift
│       ├── CDPClient.swift
│       ├── FigmaAPI.swift
│       ├── Models.swift
│       ├── DesignTokens.swift
│       └── ToolbarView.swift
├── demo/                  # CDP 调试脚本
│   ├── cdp-probe.py
│   ├── cdp-pipe.py
│   └── restart-figma.sh
└── CLAUDE.md              # 开发规范
```
