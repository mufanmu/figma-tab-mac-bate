#!/usr/bin/env python3
"""
Figma CDP Explorer — 通过 Chrome DevTools Protocol 探测 Figma 内部 JS 对象

前提: 以调试模式启动 Figma
    open -a "Figma+EX" --args --remote-debugging-port=9222

用法:
    python3 cdp-explore.py                    # 自动发现并连接
    python3 cdp-explore.py --port 9222        # 指定端口
    python3 cdp-explore.py --probe            # 连接后自动探测 Figma 内部对象
"""

import sys
import json
import time
import urllib.request
import urllib.error
import threading
import websocket

CDP_PORT = 9222
CONNECT_TIMEOUT = 10

# ============================================================
# CDP Client
# ============================================================

class CDPClient:
    def __init__(self, ws_url):
        self.ws_url = ws_url
        self.ws = None
        self.next_id = 1
        self.results = {}
        self.events = {}
        self.connected = threading.Event()

    def connect(self):
        self.ws = websocket.create_connection(self.ws_url, timeout=CONNECT_TIMEOUT)
        self.connected.set()
        print(f"[CDP] 已连接到 {self.ws_url}")

    def send(self, method, params=None, timeout=10):
        msg_id = self.next_id
        self.next_id += 1
        msg = {"id": msg_id, "method": method, "params": params or {}}

        self.ws.send(json.dumps(msg))

        while True:
            self.ws.settimeout(timeout)
            try:
                response = self.ws.recv()
            except websocket.WebSocketTimeoutException:
                print(f"[CDP] 超时等待 {method} 的响应")
                return None

            data = json.loads(response)
            if data.get("id") == msg_id:
                if "error" in data:
                    print(f"[CDP] 错误: {data['error']}")
                    return None
                return data.get("result", {})
            elif "method" in data:
                self.events[data["method"]] = data.get("params", {})
                # 继续等待我们的响应

    def evaluate(self, expression, timeout=10):
        return self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "timeout": 8000,
        }, timeout=timeout)

    def get_properties(self, object_id, timeout=10):
        return self.send("Runtime.getProperties", {
            "objectId": object_id,
            "ownProperties": True,
        }, timeout=timeout)

    def close(self):
        if self.ws:
            self.ws.close()

# ============================================================
# Target Discovery
# ============================================================

def discover_targets(port=CDP_PORT):
    url = f"http://localhost:{port}/json"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.URLError as e:
        print(f"[错误] 无法连接到 http://localhost:{port}")
        print(f"  请先以调试模式启动 Figma:")
        print(f"  open -a \"Figma+EX\" --args --remote-debugging-port={port}")
        return None
    except Exception as e:
        print(f"[错误] {e}")
        return None

def find_figma_target(port=CDP_PORT):
    targets = discover_targets(port)
    if not targets:
        return None

    print(f"\n发现 {len(targets)} 个调试目标:")
    for t in targets:
        title = t.get("title", "(无标题)")
        ttype = t.get("type", "?")
        ws = t.get("webSocketDebuggerUrl", "")
        url_short = t.get("url", "")[:80]
        print(f"  [{ttype}] {title}")
        print(f"         -> {url_short}")

    # 优先找 Figma 编辑器页面 (包含 figma.com)
    for t in targets:
        url = t.get("url", "")
        if "figma.com" in url or "figma" in url.lower():
            ws_url = t.get("webSocketDebuggerUrl", "")
            if ws_url:
                print(f"\n[选择] 目标: {t.get('title', '无标题')}")
                return ws_url

    # 回退到第一个有 WebSocket URL 的目标
    for t in targets:
        ws_url = t.get("webSocketDebuggerUrl", "")
        if ws_url:
            print(f"\n[选择] 目标: {t.get('title', '无标题')}")
            return ws_url

    print("[错误] 未找到可用的调试目标")
    return None

# ============================================================
# Figma 内部对象探测
# ============================================================

def safe_eval(client, expr, label=""):
    """执行 JS 表达式并安全地打印结果"""
    result = client.evaluate(expr)
    if result is None:
        print(f"  ✗ {label}: 超时或错误")
        return None

    val = result.get("result", {})
    vtype = val.get("type", "?")
    vdesc = val.get("description", "")[:120]
    val_short = json.dumps(val.get("value", None), default=str)[:120]

    if label:
        print(f"  ✓ {label}: [{vtype}] {vdesc or val_short or '(empty)'}")
    return result

def probe_figma_environment(client):
    """探测 Figma 内部 JS 环境，寻找可用于读取/修改设计数据的对象"""

    print("\n" + "=" * 60)
    print("Figma 内部 JS 环境探测")
    print("=" * 60)

    probes = [
        # ---- 基础探测 ----
        ("document.title", "页面标题"),
        ("window.location.href", "当前 URL"),
        ("typeof figma", "全局 figma 对象"),
        ("typeof window.figma", "window.figma"),
        ("typeof __FIGMA__", "__FIGMA__ 命名空间"),
        ("typeof __react__, typeof React", "React 框架"),

        # ---- Figma 可能的内部 API ----
        ("Object.keys(window).filter(k => k.toLowerCase().includes('figma')).slice(0,20).join(', ')", "Figma 相关全局变量"),
        ("Object.keys(window).filter(k => k.toLowerCase().includes('editor')).slice(0,10).join(', ')", "Editor 相关全局变量"),
        ("Object.keys(window).filter(k => k.toLowerCase().includes('canvas') || k.toLowerCase().includes('viewport')).slice(0,10).join(', ')", "Canvas/Viewport 相关"),

        # ---- 尝试访问内部状态 ----
        ("(()=>{try{var ks=[];for(var k in window){try{if(k.length<30&&window[k]&&typeof window[k]==='object')ks.push(k)}catch(e){}}return ks.slice(0,30).join(', ')}catch(e){return e.message}})()", "window 上的顶层对象"),

        # ---- React 组件树 ----
        ("(()=>{try{var el=document.querySelector('[data-testid]')||document.querySelector('#react-root')||document.querySelector('[class*=\"editor\"]');return el?el.tagName+':'+el.className.slice(0,80):'not-found'}catch(e){return e.message}})()", "React 根节点"),
    ]

    for expr, label in probes:
        safe_eval(client, expr, label)

def probe_selection(client):
    """尝试找到选中元素的信息"""

    print("\n" + "=" * 60)
    print("选中元素探测")
    print("=" * 60)

    selection_probes = [
        ("(()=>{try{return document.querySelector('.selection_colors--')?.textContent || 'none'}catch(e){return e.message}})()", "CSS 选择器试探1"),
        ("(()=>{try{var els=document.querySelectorAll('[class*=\"selection\"]');return els.length+' elements found'}catch(e){return 'err:'+e.message}})()", "含 'selection' 的元素数"),
        ("(()=>{try{var d=document.querySelector('[data-selection]');return d?d.getAttribute('data-selection').slice(0,200):'no data-selection attr'}catch(e){return 'err:'+e.message}})()", "data-selection 属性"),
    ]

    for expr, label in selection_probes:
        safe_eval(client, expr, label)

def probe_react_internals(client):
    """尝试通过 React fiber tree 获取状态"""

    print("\n" + "=" * 60)
    print("React Fiber Tree 探测")
    print("=" * 60)

    react_probes = [
        # 查找 React root fiber
        ("""(()=>{try{var root=document.getElementById('react-root')||document.querySelector('#root')||document.body.children[0];var fiberKey=Object.keys(root).find(k=>k.startsWith('__reactFiber'));return fiberKey||'no fiber found'}catch(e){return e.message}})()""", "React Fiber Key"),

        # 遍历 fiber tree 的顶层
        ("""(()=>{try{var root=document.getElementById('react-root')||document.querySelector('#root')||document.body.children[0];var fiberKey=Object.keys(root).find(k=>k.startsWith('__reactFiber'));if(!fiberKey)return'no fiber';var fiber=root[fiberKey];var depth=0;while(fiber&&depth<3){fiber=fiber.child;depth++}return fiber?'fiber found at depth '+depth:'no child'}catch(e){return e.message}})()""", "Fiber 遍历层级"),

        # 查找内部状态（memoizedState / pendingProps）
        ("""(()=>{try{var root=document.getElementById('react-root')||document.querySelector('#root')||document.body.children[0];var fiberKey=Object.keys(root).find(k=>k.startsWith('__reactFiber'));if(!fiberKey)return'no fiber';var fiber=root[fiberKey];var props=[];for(var k in fiber.memoizedState||{}){props.push(k)};return props.slice(0,10).join(', ')||'empty memoizedState'}catch(e){return e.message}})()""", "Fiber memoizedState"),
    ]

    for expr, label in react_probes:
        safe_eval(client, expr, label)


# ============================================================
# Main
# ============================================================

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Figma CDP Explorer")
    parser.add_argument("--port", type=int, default=CDP_PORT, help="CDP 调试端口")
    parser.add_argument("--probe", action="store_true", help="自动探测 Figma 内部对象")
    parser.add_argument("--eval", type=str, help="执行自定义 JS 表达式")
    args = parser.parse_args()

    print("Figma CDP Explorer")
    print("=" * 60)

    ws_url = find_figma_target(args.port)
    if not ws_url:
        sys.exit(1)

    client = CDPClient(ws_url)
    try:
        client.connect()

        # 启用 Runtime domain
        client.send("Runtime.enable")
        print("[CDP] Runtime domain 已启用")

        if args.eval:
            # 执行自定义 JS
            print(f"\n执行: {args.eval}")
            safe_eval(client, args.eval, "自定义表达式")
        elif args.probe:
            # 完整探测
            probe_figma_environment(client)
            probe_react_internals(client)
            probe_selection(client)
        else:
            # 默认：轻量探测
            safe_eval(client, "document.title", "页面标题")
            safe_eval(client, "typeof figma", "figma 对象")
            safe_eval(client, "Object.keys(window).filter(k=>k.toLowerCase().includes('figma')).join(', ')", "Figma 相关全局变量")

            print("\n交互模式: 输入 JS 表达式来执行 (q 退出)")
            while True:
                try:
                    expr = input("\n> ").strip()
                    if expr in ("q", "quit", "exit"):
                        break
                    if expr:
                        safe_eval(client, expr, expr)
                except (EOFError, KeyboardInterrupt):
                    break

    finally:
        client.close()
        print("\n连接已关闭")

if __name__ == "__main__":
    main()
