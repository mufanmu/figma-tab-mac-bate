#!/usr/bin/env python3
"""
Figma CDP Probe — 连接 Figma 编辑器，探测内部 JS API

前提: Figma 使用 hex-patched asar + --remote-debugging-port=9222 启动
用法: python3 cdp-probe.py
"""

import websocket
import json
import sys
import time
import threading
import urllib.request


class CDPClient:
    def __init__(self, ws_url):
        self.ws_url = ws_url
        self.ws = None
        self._next_id = 1
        self._results = {}
        self._events = []
        self._connected = False

    def connect(self, timeout=10):
        self.ws = websocket.create_connection(self.ws_url, timeout=timeout)
        self._connected = True

    def send(self, method, params=None, timeout=15):
        msg_id = self._next_id
        self._next_id += 1
        msg = {"id": msg_id, "method": method, "params": params or {}}
        self.ws.send(json.dumps(msg))

        self.ws.settimeout(timeout)
        while True:
            try:
                raw = self.ws.recv()
            except websocket.WebSocketTimeoutException:
                return None
            data = json.loads(raw)
            if data.get("id") == msg_id:
                if "error" in data:
                    return {"error": data["error"]}
                return data.get("result", {})
            elif "method" in data:
                self._events.append(data)

    def evaluate(self, expression, timeout=15):
        return self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "timeout": 10000,
        }, timeout=timeout)

    def enable_runtime(self):
        self.send("Runtime.enable")
        self.send("DOM.enable")

    def close(self):
        if self.ws:
            self.ws.close()


def discover_figma_pages(port=9222):
    url = f"http://localhost:{port}/json"
    resp = urllib.request.urlopen(url, timeout=5)
    targets = json.loads(resp.read().decode())
    return [t for t in targets
            if t.get("type") == "page"
            and "figma.com" in t.get("url", "")
            and "/file/" in t.get("url", "") or "/design/" in t.get("url", "") or "/board/" in t.get("url", "")]


def safe_eval(client, expr, label=""):
    result = client.evaluate(expr)
    if result is None:
        print(f"  \u2717 {label}: 超时")
        return None
    if "error" in result:
        print(f"  \u2717 {label}: {result['error'].get('message', '?')}")
        return None
    val = result.get("result", {})
    vtype = val.get("type", "?")
    vdesc = val.get("description", "")[:150]
    if vdesc:
        print(f"  \u2713 {label}: [{vtype}] {vdesc}")
    else:
        val_raw = json.dumps(val.get("value", None), default=str)[:150]
        print(f"  \u2713 {label}: [{vtype}] {val_raw}")
    return result


def probe_all(client):
    print("\n" + "=" * 70)
    print("  探测 1: 基础环境")
    print("=" * 70)
    for expr, label in [
        ("document.title", "页面标题"),
        ("window.location.href", "URL"),
        ("typeof figma", "typeof figma"),
        ("typeof window.figma", "typeof window.figma"),
        ("typeof window.__FIGMA__", "typeof __FIGMA__"),
        ("typeof window.__app__", "typeof __app__"),
    ]:
        safe_eval(client, expr, label)

    print("\n" + "=" * 70)
    print("  探测 2: Figma/Editor 全局变量")
    print("=" * 70)
    for expr, label in [
        ("Object.keys(window).filter(k=>k.toLowerCase().includes('figma')||k.toLowerCase().includes('editor')||k.toLowerCase().includes('canvas')).join(', ')",
         "包含 figma/editor/canvas 的全局变量"),
        ("Object.keys(window).filter(k=>k.length<=4 && k.match(/^[A-Z]/)).join(', ')",
         "大写短变量名 (可能的内部 API)"),
    ]:
        safe_eval(client, expr, label)

    print("\n" + "=" * 70)
    print("  探测 3: React Fiber Tree")
    print("=" * 70)
    for expr, label in [
        ("""(()=>{
            var el = document.getElementById('react-root') || document.querySelector('#root') || document.body.firstElementChild;
            if(!el) return 'no root element';
            var key = Object.keys(el).find(k=>k.startsWith('__reactFiber')||k.startsWith('__reactInternalInstance'));
            return key || 'no fiber key found. keys: ' + Object.keys(el).slice(0,5).join(',');
        })()""", "React Fiber 根节点"),
        ("""(()=>{
            var el = document.getElementById('react-root') || document.querySelector('#root') || document.body.firstElementChild;
            if(!el) return 'no root';
            var key = Object.keys(el).find(k=>k.startsWith('__reactFiber')||k.startsWith('__reactInternalInstance'));
            if(!key) return 'no key';
            var fiber = el[key];
            var types = [];
            function walk(f, d) {
                if(!f || d>5) return;
                var t = f.type;
                if(t) {
                    var tn = typeof t === 'string' ? t : (t.displayName || t.name || 'anon');
                    if(tn.length < 40) types.push(tn);
                }
                if(f.child) walk(f.child, d+1);
                if(f.sibling) walk(f.sibling, d);
            }
            walk(fiber, 0);
            return types.slice(0,30).join(' | ');
        })()""", "React 组件树 (前30个)"),
    ]:
        safe_eval(client, expr, label)

    print("\n" + "=" * 70)
    print("  探测 4: 潜在 Figma 内部 API")
    print("=" * 70)
    for expr, label in [
        # 搜索内部 API 对象
        ("""(()=>{
            var found = [];
            var searchTerms = ['figma', 'editor', 'canvas', 'plugin', 'selection', 'node', 'layer', 'tool'];
            for (var k in window) {
                try {
                    if (window[k] && typeof window[k] === 'object' && window[k] !== window) {
                        var kl = k.toLowerCase();
                        if (searchTerms.some(t => kl.includes(t))) {
                            found.push(k);
                            if (found.length >= 20) break;
                        }
                    }
                } catch(e) {}
            }
            return found.join(', ');
        })()""", "Figma 相关对象 (20个)"),
        # 尝试访问 __REACT_DEVTOOLS_GLOBAL_HOOK__
        ("typeof window.__REACT_DEVTOOLS_GLOBAL_HOOK__", "React DevTools Hook"),
        # 查看 React root
        ("""(()=>{
            var hook = window.__REACT_DEVTOOLS_GLOBAL_HOOK__;
            if(!hook) return 'no react hook';
            var renderers = hook.renderers;
            if(!renderers || !renderers.size) return 'no renderers';
            var result = [];
            renderers.forEach(function(r, key) {
                result.push('renderer ' + key + ': version ' + (r.version || '?'));
            });
            return result.join('; ');
        })()""", "React Renderer 信息"),
        # 获取 React Fiber root
        ("""(()=>{
            var hook = window.__REACT_DEVTOOLS_GLOBAL_HOOK__;
            if(!hook) return 'no hook';
            try {
                var fiberRoots = [];
                if(hook.getFiberRoots) {
                    var roots = hook.getFiberRoots(1); // React 18+
                    fiberRoots.push('getFiberRoots(1): ' + (roots ? roots.size + ' roots' : 'null'));
                }
                return fiberRoots.join('; ') || 'no roots found';
            } catch(e) {
                return 'error: ' + e.message;
            }
        })()""", "Fiber Roots"),
    ]:
        safe_eval(client, expr, label)


def main():
    print("Figma CDP Probe — 探测 Figma 内部 JS API\n")

    # 发现 Figma 编辑器页面
    pages = discover_figma_pages()
    if not pages:
        print("[错误] 未找到 Figma 编辑器页面。请确保:")
        print("  1. Figma 以 --remote-debugging-port=9222 启动")
        print("  2. 至少打开一个设计文件")
        sys.exit(1)

    print(f"找到 {len(pages)} 个 Figma 设计页面:")
    for p in pages:
        print(f"  - {p.get('title', '?')[:60]}")
        print(f"    {p.get('url', '')[:100]}")

    # 连接第一个页面
    target = pages[0]
    ws_url = target["webSocketDebuggerUrl"]
    title = target.get("title", "?")
    print(f"\n连接: {title}")
    print(f"WS: {ws_url}\n")

    client = CDPClient(ws_url)
    try:
        client.connect()
        client.enable_runtime()
        print("[CDP] 已连接, Runtime domain 已启用\n")

        probe_all(client)

    except Exception as e:
        print(f"[错误] {e}")
    finally:
        client.close()
        print("\n连接已关闭")


if __name__ == "__main__":
    main()
