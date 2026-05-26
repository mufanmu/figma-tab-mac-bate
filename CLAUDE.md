# Figma CDP Toolbar - Development Guidelines

## Project Overview

macOS 原生浮动工具栏（NSPanel），通过 Chrome DevTools Protocol 直接与 Figma 桌面端通信，
无需插件即可读取/修改选中元素属性。工具栏始终固定在选中元素上方，随缩放和平移跟随。

## Tech Stack

- **Frontend**: SwiftUI + AppKit (NSPanel, borderless style)
- **Figma Bridge**: Chrome DevTools Protocol (WebSocket on localhost:9222)
- **No plugin, no backend server required**

## Architecture

```
Figma Desktop (hex-patched asar)
    ↕ WebSocket CDP (localhost:9222)
SwiftUI NSPanel (cdp-toolbar)
    ↕ Runtime.evaluate("figma.*")
Figma Editor JS Context
```

## Principles

### 1. Think Before Coding
- 明确表述假设
- 多个方案时呈现权衡
- 需求不明确时停止并询问

### 2. Simplicity First
- 不添加超出请求的功能
- 单次使用的代码不做抽象
- 不过早引入灵活性或可配置性

### 3. Surgical Changes
- 只修改必要的部分
- 不重构相邻代码、注释或格式
- 匹配已有风格，即使与你的偏好不同

### 4. Goal-Driven Execution
- 编码前定义可验证的成功标准

## Key Technical Details

### CDP 通道
- Figma 必须使用 hex-patched app.asar 启动（跳过 `removeSwitch("remote-debugging-port")`）
- 启动命令: `open -a "Figma+EX" --args '--remote-debugging-port=9222' '--remote-allow-origins=*'`
- 通过 `http://localhost:9222/json` 发现目标页面
- WebSocket 连接到 Figma 编辑器页面

### 坐标定位
- 使用 `figma.viewport.bounds` (不是 viewport.center + zoom) 做画布→屏幕映射
- 公式: `domX = canvas.left + (nodeX - vb.x) / vb.width * canvas.width`
- Y 轴: `domY = canvas.top + (nodeY - vb.y) / vb.height * canvas.height`
- `vb.y` 是视口上沿（Y-down 坐标系）
- 间距使用画布单位（常用 10 单位），非屏幕像素，缩放下保持视觉一致

### CDPClient
- `URLSession` 必须存为类属性（不能是局部变量，否则 WebSocket 断连）
- `Runtime.evaluate` 的返回值在 `result.result.value`（双层嵌套）
- `awaitPromise: true` 用于异步 Figma API（如 loadFontAsync）

### NSPanel
- `styleMask: [.borderless, .nonactivatingPanel]`
- `orderFront(nil)` — 永远不要改为 `makeKeyAndOrderFront`（会抢夺焦点）
- `level: .floating` + `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`
- TextField 需要面板成为 Key Window：创建 `FloatingPanel: NSPanel` 子类，重写 `canBecomeKey { true }`。.nonactivatingPanel 仍阻止 app 激活，仅允许键盘输入

## 输入框设计规范

工具栏中所有需要用户输入的文本框，统一遵循以下规范：

### 占位态（未输入时）
- 输入框显示当前值（如字体名、数值），**不透明度 35%**
- 光标在输入框最前面闪烁，随时可输入
- 占位文字不响应点击（`allowsHitTesting(false)`），点击事件穿透到 TextField

### 输入态（输入中）
- 用户键入的文字以**不透明度 100%** 显示
- 占位文字自动隐藏
- 输入内容为纯文本（不格式化、不校验）

### 选中态（选择后）
- 清空输入内容（`searchText = ""`）
- 输入框回退为占位态，显示新的当前值（降透明度）
- 如有下拉列表，自动关闭

### 交互规则
- 输入框获得焦点 → 显示下拉/建议列表（如有）
- 输入内容变化 → 实时过滤列表
- 点击外部或按 Enter → 关闭下拉列表
- 切换数据源（如切换 Figma 选中节点）→ 自动清空输入框

## 项目结构

```
cdp-toolbar/
├── Package.swift
└── Sources/FigmaCDPToolbar/
    ├── main.swift           # @main 入口 + MenuBarExtra
    ├── AppDelegate.swift    # NSPanel 创建 + CDP 轮询 + 定位
    ├── CDPClient.swift      # WebSocket CDP 通信
    ├── FigmaAPI.swift       # figma.* API 封装
    ├── Models.swift         # 数据模型
    ├── ToolbarView.swift    # 工具栏 UI
    └── DesignTokens.swift   # 设计系统
```

## 构建 & 运行

```bash
cd cdp-toolbar && swift build && .build/debug/FigmaCDPToolbar &
```
