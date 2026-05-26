#!/usr/bin/env python3
"""
Figma CDP Pipe Explorer v2 — 修复版

关键发现: --remote-debugging-pipe 在 Figma 中未被 disable
  (只 removeSwitch 了 --remote-debugging-port)

管道协议:
  stdout: JSON message + '\0' null byte
  stdin:  JSON message + '\0' null byte
"""

import subprocess
import json
import sys
import time
import threading
import os
import signal
import select

FIGMA_BIN = "/Applications/Figma+EX.app/Contents/MacOS/Figma"

class FigmaDevTools:
    def __init__(self):
        self.proc = None
        self.next_id = 1
        self.responses = {}
        self.targets = {}
        self._running = False
        self._read_thread = None
        self._buffer = b""
        self._lock = threading.Lock()
        self._events = []

    def launch(self):
        """启动 Figma 并建立管道通信"""
        print("[启动] 正在关闭旧 Figma 实例...")
        subprocess.run(["osascript", "-e", 'tell application "Figma+EX" to quit'],
                       capture_output=True)
        time.sleep(3)

        print("[启动] 以 devtools-pipe 模式启动...")
        self.proc = subprocess.Popen(
            [FIGMA_BIN, "--remote-debugging-pipe"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,  # unbuffered
        )

        self._running = True
        self._read_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self._read_thread.start()

        # 等待 Figma 初始化并接收初始消息
        print("[启动] 等待 Figma 初始化...")
        waited = 0
        while waited < 15 and self.proc.poll() is None:
            time.sleep(0.5)
            waited += 0.5
            if len(self._events) > 0:
                break
            if waited >= 3:
                print(f"[启动]  等待中 ({waited:.0f}s)...")

        if self.proc.poll() is not None:
            print(f"[错误] Figma 意外退出 (code: {self.proc.returncode})")
            stderr = self.proc.stderr.read().decode('utf-8', errors='replace')
            devtools_lines = [l for l in stderr.split('\n') if 'devtools' in l.lower()]
            if devtools_lines:
                print("[错误] DevTools 日志:")
                for l in devtools_lines[:5]:
                    print(f"  {l[:200]}")
            pipe_lines = [l for l in stderr.split('\n') if 'pipe' in l.lower()]
            if pipe_lines:
                print("[错误] 管道日志:")
                for l in pipe_lines[:5]:
                    print(f"  {l[:200]}")
            return False

        print(f"[启动] Figma 运行中. 收到 {len(self._events)} 个初始事件.")
        # Print received events
        for e in self._events:
            method = e.get("method", "")
            params = e.get("params", {})
            if method:
                info = json.dumps(params, default=str)[:150]
                print(f"  [{method}] {info}")
        return True

    def _read_stdout(self):
        """读取 Figma stdout 上的 DevTools 消息"""
        while self._running and self.proc and self.proc.poll() is None:
            try:
                ready, _, _ = select.select([self.proc.stdout], [], [], 0.1)
                if not ready:
                    continue
                data = os.read(self.proc.stdout.fileno(), 65536)
                if not data:
                    break
                with self._lock:
                    self._buffer += data
                    self._process_buffer()
            except Exception as e:
                if self._running:
                    print(f"[错误] read_stdout: {e}")
                break

    def _process_buffer(self):
        """处理缓冲区中的消息"""
        while b'\x00' in self._buffer:
            msg_bytes, self._buffer = self._buffer.split(b'\x00', 1)
            if msg_bytes:
                try:
                    msg = json.loads(msg_bytes.decode('utf-8'))
                    msg_id = msg.get("id")
                    method = msg.get("method")
                    if msg_id is not None:
                        self.responses[msg_id] = msg
                    elif method:
                        self._events.append(msg)
                        if method == "Target.targetCreated":
                            info = msg.get("params", {}).get("targetInfo", {})
                            if info:
                                self.targets[info["targetId"]] = info
                except Exception:
                    pass

    def send(self, method, params=None, timeout=10):
        """发送 CDP 命令并等待响应"""
        msg_id = self.next_id
        self.next_id += 1
        msg = {"id": msg_id, "method": method, "params": params or {}}
        data = json.dumps(msg).encode('utf-8') + b'\x00'

        try:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()
        except BrokenPipeError:
            print("[错误] 管道已断开")
            return None

        start = time.time()
        while time.time() - start < timeout:
            if msg_id in self.responses:
                result = self.responses.pop(msg_id)
                if "error" in result:
                    print(f"[CDP错误] {result['error']}")
                    return None
                return result.get("result", {})
            time.sleep(0.01)

        print(f"[超时] {method}")
        self.responses.pop(msg_id, None)
        return None

    def evaluate(self, expression, timeout=10):
        return self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
        }, timeout=timeout)

    def get_editor_target(self):
        """找到最可能是编辑器页面的 target"""
        # 先列出所有 page 类型 targets
        pages = {tid: info for tid, info in self.targets.items()
                  if info.get("type") == "page"}
        print(f"\n[发现] {len(pages)} 个页面目标:")
        for tid, info in pages.items():
            title = info.get("title", "?")[:60]
            url = info.get("url", "")[:80]
            print(f"  [{tid[:12]}...] {title}")
            if url:
                print(f"           {url}")

        # 尝试找到 figma.com 相关页面
        for tid, info in pages.items():
            url = info.get("url", "")
            if "figma.com" in url:
                return tid

        # 回退到第一个页面
        if pages:
            return list(pages.keys())[0]
        return None

    def attach_to_target(self, target_id):
        """附加到指定 target 获取 session"""
        result = self.send("Target.attachToTarget", {
            "targetId": target_id,
            "flatten": True
        })
        if result:
            return result.get("sessionId")
        return None

    def shutdown(self):
        """关闭 Figma"""
        self._running = False
        if self.proc and self.proc.poll() is None:
            print("\n[关闭] 正在关闭 Figma...")
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except:
                self.proc.kill()

# ============================================================
# 探测逻辑
# ============================================================

def probe(figma):
    """自动探测 Figma 内部 API"""
    print("\n" + "=" * 60)
    print("探测 Figma 内部 JS 环境")
    print("=" * 60)

    # 先找编辑器 target 并 attach
    editor_id = figma.get_editor_target()
    if not editor_id:
        print("[错误] 找不到编辑器页面")
        return

    session_id = figma.attach_to_target(editor_id)
    if not session_id:
        print("[错误] 无法附加到编辑器页面")
        return

    print(f"\n[连接] Session: {session_id[:20]}...")

    probes = [
        ("document.title", "页面标题"),
        ("window.location.href", "当前 URL"),
        # Figma 内部对象
        ("typeof figma", "typeof figma"),
        ("typeof window.figma", "typeof window.figma"),
        ("typeof window.__FIGMA__", "typeof __FIGMA__"),
        # 尝试枚举 Figma 相关的全局变量
        ("Object.keys(window).filter(function(k){return k.toLowerCase().indexOf('figma')>=0||k.toLowerCase().indexOf('editor')>=0}).join(', ')",
         "Figma/Editor 全局变量"),
        # React
        ("typeof React", "typeof React"),
        ("typeof window.React", "typeof window.React"),
        # 页面结构
        ("document.querySelectorAll('[id]').length + ' elements with id'",
         "带 id 的元素数"),
        ("document.querySelector('[class*=\"app\"]') ? 'found app container' : 'not found'",
         "App 容器"),
    ]

    for expr, label in probes:
        result = figma.evaluate(expr)
        if result is None:
            print(f"  \u2717 {label}: 无响应")
            continue
        val = result.get("result", {})
        vtype = val.get("type", "?")
        vdesc = val.get("description", "")[:120]
        if vdesc:
            print(f"  \u2713 {label}: [{vtype}] {vdesc}")
        else:
            vval = json.dumps(val.get("value"), default=str)[:120]
            print(f"  \u2713 {label}: [{vtype}] {vval}")

# ============================================================
# 交互模式
# ============================================================

def interactive(figma):
    editor_id = figma.get_editor_target()
    if editor_id:
        figma.attach_to_target(editor_id)

    print("\n交互模式 (JS 表达式，q 退出):")
    while True:
        try:
            expr = input("\n> ").strip()
            if expr.lower() in ("q", "quit", "exit"):
                break
            if expr:
                result = figma.evaluate(expr)
                if result:
                    val = result.get("result", {})
                    print(f"  [{val.get('type', '?')}] {json.dumps(val.get('value') or val.get('description',''), default=str)[:200]}")
        except (EOFError, KeyboardInterrupt):
            break

# ============================================================
# Main
# ============================================================

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()

    figma = FigmaDevTools()
    try:
        if not figma.launch():
            print("[失败] Figma 启动失败")
            sys.exit(1)

        if args.probe:
            probe(figma)
        else:
            interactive(figma)

    finally:
        figma.shutdown()

if __name__ == "__main__":
    main()
