# Figma CDP Toolbar

> **v1.2** — macOS 原生浮动工具栏，通过 CDP 直连 Figma，无需插件。

## v1.2 更新

- **文字编辑**：字号、对齐（左/中/右/两端）、行高、字距、段距、缩进、下划线、删除线、大小写、自动调整尺寸、填充色
- **字体选择**：预加载 50 字体，Popover 滚动列表，自动定位到当前字体，滚动懒加载
- **形状编辑**：填充色、填充不透明度、描边色、描边粗细、圆角、不透明度
- **多选对齐**：水平（左/中/右）、垂直（上/中/下）、水平分布、垂直分布
- **自适应宽度**：工具栏宽度随内容自动调整
- **智能隐藏**：切到其他应用自动隐藏，仅 Figma 激活时显示
- **一键响应**：`acceptsFirstMouse` 消除双击问题
- **颜色编辑器**：SB 拾色平面 + 色相/Alpha 滑块 + HEX/HSB/RGB 输入 + 拾色器 + 预设颜色（Popover 弹出）
- **填充/描边分离**：工具栏色块按钮（实心圆/空心环），点击各自弹出编辑器
- **描边控制**：粗细滑块 + 内部/居中/外部位置选择
- **预设颜色**：快捷切换白色/黑色/删除颜色（None.svg）
- **实时更新**：拖动色板即时写入 Figma，无需确认

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
| 颜色编辑器 | `ToolbarView.swift`（AntColorPicker） |
| 设计系统 | `DesignTokens.swift` |
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
