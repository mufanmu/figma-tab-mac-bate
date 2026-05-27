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

### 5. 中文沟通
- 所有思考过程、问题分析、方案讨论均使用中文
- 代码、注释、日志保持英文不变
- 方便用户即时理解思路，无需翻译

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

## 工具栏布局约束（CRITICAL）

### 固定宽度：1250px

工具栏使用 `.frame(width: 1250)` 固定宽度，**禁止使用 `.fixedSize()` 或自适应宽度方案**。

**原因：** `.fixedSize()` 在 NSHostingView 中会导致 SwiftUI 内部坐标映射偏移，造成 hit-test 区域与视觉渲染位置不一致（点击按钮右侧会触发相邻按钮）。固定宽度可以完全避免这个问题。

### 修改布局时的检查清单

增加、删除、调整工具栏控件（按钮、输入框、分隔符等）后，**必须检查实际总宽度**：

1. 控件宽度估算（大约值）：
   - `fontPicker`: ~230px
   - `NumField`: ~60px
   - `LineHeightField`: ~60px
   - 对齐按钮组（4 个 32px + 间距）: ~134px
   - `decorationButtons`（2 个 32px + 间距）: ~66px
   - `textCasePicker`（4 个 32px + 间距）: ~134px
   - `autoResizePicker`（3 个 24px + 间距）: ~76px
   - `ColorPicker`（scaleEffect 0.75）: ~17px
   - `Separator`: 1px
   - `opacitySlider`: ~90px

2. HStack spacing: `spacing: 6`（textToolbar）/ `spacing: 4`（alignToolbar）

3. 容器 padding: `.padding(.horizontal, 8)` = 左右各 8px

4. **确保总宽度 ≤ 1250px。如果超出，调整 `.frame(width:)` 的值，同步修改以下三处：**
   - `ToolbarView.swift` → `.frame(width: N)`
   - `AppDelegate.swift` → `setupPanel()` → `contentRect` 和 `hostingView.setFrameSize`
   - `AppDelegate.swift` → `updatePanelPosition()` → `panel.setFrame` 中的 `qx - N/2` 和宽度值

### 已知问题：`.fixedSize()` + NSHostingView = 点击偏移

经过多次实验确认：任何形式的 `.fixedSize()`（包括搭配 `.frame(alignment:)`、`clipsToBounds`、固定 1200px NSHostingView + 面板裁剪、`intrinsicContentSize` 等方案）在 NSHostingView 中都会导致 hit-test 坐标系偏移。**唯一可靠方案是 `.frame(width: 固定值)`。**

## 构建 & 运行

```bash
swift build --package-path cdp-toolbar && cdp-toolbar/.build/debug/FigmaCDPToolbar &
```
