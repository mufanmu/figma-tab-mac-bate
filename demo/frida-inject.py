#!/usr/bin/env python3
"""
Frida JS Injector — 注入 JavaScript 到 Figma 渲染进程

Figma 是基于 Electron 的应用，渲染进程运行 V8 + Blink。
通过 Frida 可以 hook 进程内部函数，注入自己的代码。

方案: 不直接注入 Figma 的 JS 上下文 (V8 隔离困难)，
      而是通过 hook Chromium 的 IPC 或 DOM 操作来间接通信。

更实用的方案: 注入一个全局事件监听脚本来桥接 Frida ↔ Figma JS。
"""

import frida
import sys
import json
import time
import subprocess


def get_figma_renderers():
    """获取所有 Figma 渲染进程 PID"""
    result = subprocess.run(
        ["ps", "aux"],
        capture_output=True, text=True
    )
    renderers = []
    for line in result.stdout.split('\n'):
        if 'Figma Helper (Renderer)' in line and '--type=renderer' in line:
            parts = line.split()
            if len(parts) >= 2:
                pid = int(parts[1])
                # 提取 renderer-client-id
                import re
                match = re.search(r'--renderer-client-id=(\d+)', line)
                client_id = match.group(1) if match else '?'
                renderers.append((pid, client_id))
    return renderers


def on_message(message, data):
    """处理 Frida 脚本发回的消息"""
    if message['type'] == 'send':
        payload = message.get('payload', '')
        print(f"  [Frida] {payload}")
    elif message['type'] == 'error':
        print(f"  [Error] {message.get('description', message)}")


def inject_into_renderer(pid, client_id):
    """向指定渲染进程注入 JS"""
    print(f"\n[注入] 渲染进程 PID={pid}, client-id={client_id}")

    try:
        session = frida.attach(pid)
    except frida.ProcessNotRespondingError:
        print(f"  [失败] 进程无响应")
        return None
    except Exception as e:
        print(f"  [失败] {e}")
        return None

    # 尝试 1: 通过 V8 内部 API 执行 JS
    # Frida 的 JavaScript API 运行在 Duktape 中，不是 V8
    # 我们需要找到 V8 Isolate 并调用其 Evaluate 方法
    
    script_code = """
// 方案 A: 查找 V8 函数并 hook
// V8 的 v8::Script::Compile 和 v8::Script::Run 符号
    
// 方案 B: Hook Blink 层
// 在 Chromium 中，evaluateJavaScript 最终调用
// blink::WebLocalFrame::ExecuteScript

// 方案 C: 通过 DOM 注入
// 使用 Accessibility API 或修改渲染进程的内存

// 先用最简单的: 枚举进程中的模块和符号
const modules = Process.enumerateModules();
const v8Modules = modules.filter(m => m.name.includes('v8') || m.name.includes('V8'));
const blinkModules = modules.filter(m => m.name.includes('blink') || m.name.includes('Blink') || m.name.includes('content'));

console.log('Modules found:');
console.log('  V8 modules: ' + v8Modules.map(m => m.name).join(', '));
console.log('  Blink/Content modules: ' + blinkModules.map(m => m.name).join(', '));

// 查找可能包含 WebFrame::executeScript 的模块
const frameworkModules = modules.filter(m => 
    m.name.includes('Figma') || m.name.includes('Electron') || m.name.includes('Chromium')
);
console.log('  Framework modules: ' + frameworkModules.map(m => m.name).join(', '));

// 尝试查找 Objective-C WebView
if (ObjC.available) {
    console.log('Objective-C runtime available');
    
    // 查找 WKWebView 或相关的 WebView
    try {
        const webViewClasses = [
            'WKWebView', 'WebView', 'FigmaWebView', 'ElectronWebView'
        ];
        for (const cls of webViewClasses) {
            try {
                const c = ObjC.classes[cls];
                if (c) {
                    console.log('  Found class: ' + cls);
                    // 如果是 electron，renderer 进程用的是 Chromium Content API
                    // 不是 WKWebView
                }
            } catch(e) {}
        }
    } catch(e) {
        console.log('  ObjC class search error: ' + e);
    }
} else {
    console.log('Objective-C runtime not available');
}

// 方案 D: 直接修改 DOM 元素的内容
// 找到 document 对象的内存地址并修改
// 需要知道 V8 Isolate 的地址

send({
    module_count: modules.length,
    v8_modules: v8Modules.map(m => m.name),
    framework_modules: frameworkModules.map(m => ({name: m.name, base: m.base, size: m.size}))
});
"""

    try:
        script = session.create_script(script_code)
        script.on('message', lambda msg, data: on_message(msg, data))
        script.load()
        
        # 等待脚本执行
        time.sleep(3)
        
        # 获取结果
        script.unload()
        session.detach()
    except Exception as e:
        print(f"  [脚本错误] {e}")
        session.detach()
        return None

    return None


def inject_simple_js(pid, client_id):
    """方案 E: 通过修改 Chromium 的渲染管道注入 JS
    
    思路: Chromium 的渲染进程通过 Mojo IPC 与主进程通信。
    我们可以 hook Mojo 消息处理，在特定消息类型中注入我们的脚本。
    
    但更简单的方式: 通过修改渲染进程的内存来注入 script 元素。
    这在 Chromium sandbox 中几乎不可能。
    """
    
    print(f"\n[方案 E] 渲染进程 PID={pid}")
    
    try:
        session = frida.attach(pid)
    except Exception as e:
        print(f"  [失败] {e}")
        return None

    script_code = """
// 尝试通过 CEF/Chromium 的内部 API 访问 DOM
// 在 renderer 进程中，content::RenderFrame 持有 blink::WebLocalFrame
// blink::WebLocalFrame 提供 executeScript 方法

// 首先找到 content::RenderFrameImpl 的实例
// 这些通常通过 vtable 和 RTTI 可以找到

// 更简单: hook console.log 来查看输出
// 或者 hook window.postMessage 来拦截消息

// 实际上，最实用的方式是找到 Node.js/Electron IPC
// Figma 的渲染进程通过 electron 的 contextBridge 或 ipcRenderer 通信

// 让我们搜索 electron 相关的符号
const modules = Process.enumerateModules();
const electronModules = modules.filter(m => {
    const name = m.name.toLowerCase();
    return name.includes('electron') || name.includes('node') || name === 'ffmpeg';
});

console.log('Electron-related modules:');
for (const m of electronModules) {
    console.log(`  ${m.name} @ ${m.base} (${m.size} bytes)`);
}

// 查找可能的通信管道
// 在 macOS 上，Chromium 渲染进程通过 Mach ports 和 Unix sockets 通信
send(JSON.stringify({
    electron_modules: electronModules.map(m => ({name: m.name, path: m.path}))
}));
"""

    try:
        script = session.create_script(script_code)
        script.on('message', lambda msg, data: on_message(msg, data))
        script.load()
        time.sleep(2)
        script.unload()
        session.detach()
    except Exception as e:
        print(f"  [脚本错误] {e}")
        session.detach()


def main():
    print("Figma Frida JS Injector")
    print("=" * 60)

    renderers = get_figma_renderers()
    if not renderers:
        print("[错误] 没有找到 Figma 渲染进程。请先启动 Figma。")
        sys.exit(1)

    print(f"\n找到 {len(renderers)} 个渲染进程:")
    for pid, cid in renderers:
        print(f"  PID={pid}, client-id={cid}")

    # 选择 client-id 最小的（通常是主编辑器页面）
    # 根据观察，client-id=5 或 6 是主编辑器
    target = None
    for pid, cid in sorted(renderers, key=lambda x: int(x[1]) if x[1].isdigit() else 999):
        if cid.isdigit() and int(cid) <= 8:
            target = (pid, cid)
            break

    if not target and renderers:
        target = renderers[0]

    if target:
        print(f"\n选择目标: PID={target[0]}, client-id={target[1]}")
        inject_into_renderer(target[0], target[1])
    else:
        print("[错误] 没有可用的渲染进程")


if __name__ == "__main__":
    main()
