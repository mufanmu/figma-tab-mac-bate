#!/usr/bin/env python3
"""
Figma CDP Pipe Explorer — 通过 --remote-debugging-pipe 双向管道连接 Figma

Figma 的 main.js 中有这行代码移除了 --remote-debugging-port 开关:
  .app.commandLine.removeSwitch("remote-debugging-port")
但 --remote-debugging-pipe 开关未被移除，所以 pipe 模式可用。

DevTools Pipe Protocol:
  - stdout (Figma -> 客户端): JSON 消息 + '\0' 终止符
  - stdin  (客户端 -> Figma): JSON 消息 + '\0' 终止符

用法:
    python3 cdp-pipe.py                    # 启动 Figma 并交互
    python3 cdp-pipe.py --probe            # 自动探测内部 API
"""

import subprocess
import json
import sys
import time
import threading
import signal
import os

FIGMA_BIN = "/Applications/Figma+EX.app/Contents/MacOS/Figma"

# ============================================================
# Pipe Protocol
# ============================================================

class DevToolsPipe:
    def __init__(self, proc):
        self.proc = proc
        self.next_id = 1
        self.pending = {}
        self.events = []
        self._running = True
        self.targets = {}
        self._reader_thread = None

    def start(self):
        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()

    def _read_loop(self):
        buffer = b""
        while self._running and self.proc.poll() is None:
            try:
                byte = self.proc.stdout.read(1)
                if not byte:
                    break
                if byte == b'\0':
                    if buffer:
                        try:
                            msg = json.loads(buffer.decode('utf-8'))
                            self._handle_message(msg)
                        except json.JSONDecodeError as e:
                            print(f"[WARN] JSON decode error: {e}")
                            print(f"        raw: {buffer[:200]}")
                    buffer = b""
                else:
                    buffer += byte
            except Exception as e:
                print(f"[ERROR] read_loop: {e}")
                break
        self._running = False

    def _handle_message(self, msg):
        msg_id = msg.get("id")
        if msg_id is not None and msg_id in self.pending:
            self.pending[msg_id] = msg
            return

        method = msg.get("method", "")
        if method:
            self.events.append(msg)
            if method == "Target.targetCreated":
                info = msg.get("params", {}).get("targetInfo", {})
                tid = info.get("targetId", "?")
                self.targets[tid] = info
                print(f"  [target] {info.get('type', '?')}: {info.get('title', '?')[:60]}")
                print(f"           url: {info.get('url', '')[:80]}")
            elif method == "Target.targetInfoChanged":
                info = msg.get("params", {}).get("targetInfo", {})
                tid = info.get("targetId", "?")
                self.targets[tid] = info
            return

    def send(self, method, params=None, timeout=10):
        msg_id = self.next_id
        self.next_id += 1
        msg = {"id": msg_id, "method": method, "params": params or {}}

        data = json.dumps(msg).encode('utf-8') + b'\0'
        try:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()
        except BrokenPipeError:
            print("[ERROR] Broken pipe - Figma may have exited")
            return None

        start = time.time()
        while (time.time() - start) < timeout:
            if msg_id in self.pending:
                result = self.pending.pop(msg_id)
                if "error" in result:
                    print(f"[CDP ERROR] {result['error']}")
                    return None
                return result.get("result", {})
            time.sleep(0.01)

        print(f"[TIMEOUT] {method} 无响应")
        self.pending.pop(msg_id, None)
        return None

    def evaluate(self, expression, timeout=10):
        return self.send("Runtime.evaluate", {
            "expression": expression,
            "returnByValue": True,
            "timeout": 8000,
        }, timeout=timeout)

    def get_targets(self):
        result = self.send("Target.getTargets")
        if result:
            for t in result.get("targetInfos", []):
                tid = t.get("targetId", "?")
                self.targets[tid] = t
        return self.targets

    def attach_to_target(self, target_id):
        result = self.send("Target.attachToTarget", {
            "targetId": target_id,
            "flatten": True
        })
        if result:
            session_id = result.get("sessionId", "")
            return session_id
        return None

    def stop(self):
        self._running = False
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except:
            self.proc.kill()

# ============================================================
# Main
# ============================================================

def launch_figma():
    print(f"正在启动 Figma (pipe 模式)...")
    proc = subprocess.Popen(
        [FIGMA_BIN, "--remote-debugging-pipe"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ},  # 保持环境变量
    )
    return proc

def safe_eval(pipe, expr, label=""):
    result = pipe.evaluate(expr)
    if result is None:
        print(f"  \u2717 {label}: 无响应或超时")
        return None
    val = result.get("result", {})
    vtype = val.get("type", "?")
    vdesc = val.get("description", "")[:120]
    val_short = json.dumps(val.get("value", None), default=str)[:120]
    if label:
        print(f"  \u2713 {label}: [{vtype}] {vdesc or val_short or '(empty)'}")
    return result

def probe_environment(pipe):
    """探测 Figma 内部 JS 环境"""
    print("\n" + "=" * 60)
    print("探测 Figma 内部 JS 环境")
    print("=" * 60)

    probes = [
        ("document.title", "页面标题"),
        ("window.location.href", "当前 URL"),
        ("typeof figma", "全局 figma"),
        ("typeof window.__FIGMA__", "__FIGMA__"),
        ("typeof React", "React"),
        ("Object.keys(window).filter(k=>k.match(/figma|FIGMA/i)).join(', ')",
         "Figma 相关全局变量"),
    ]

    for expr, label in probes:
        safe_eval(pipe, expr, label)

def probe_editor(pipe):
    """探测编辑器内部状态"""
    print("\n" + "=" * 60)
    print("探测编辑器内部状态")
    print("=" * 60)

    react_probes = [
        ("""(()=>{
            var el=document.querySelector('[class*="app"]')||document.body.firstElementChild;
            var key=Object.keys(el).find(k=>k.startsWith('__reactFiber'));
            return key||'no fiber found'
        })()""", "React Fiber 根"),
        ("""(()=>{
            var el=document.querySelector('[class*="app"]')||document.body.firstElementChild;
            var key=Object.keys(el).find(k=>k.startsWith('__reactFiber'));
            if(!key) return 'no fiber';
            var fiber=el[key];
            var found=[];
            function walk(f,d){if(d>4||!f)return;var t=f.type;if(t&&typeof t==='string'&&t.match(/canvas|editor|view/i))found.push(t);if(f.child)walk(f.child,d+1);if(f.sibling)walk(f.sibling,d)}
            walk(fiber,0);
            return found.join(', ')||'nothing found'
        })()""", "Fiber 中的 canvas/editor 组件"),
        ("""(()=>{
            var allObjs=[];
            for(var k in window){try{if(window[k]&&typeof window[k]==='object'&&window[k]!==window)allObjs.push(k)}catch(e){}}
            return allObjs.filter(k=>k.length<=3 && k.length>1).join(', ')
        })()""", "窗口顶层短名对象"),
    ]

    for expr, label in react_probes:
        safe_eval(pipe, expr, label)

def interactive(pipe):
    print("\n交互模式 (输入 JS 表达式，/q 退出):")
    while True:
        try:
            expr = input("\n> ").strip()
            if expr in ("/q", "/quit", "/exit"):
                break
            if expr == "/targets":
                targets = pipe.get_targets()
                for tid, info in targets.items():
                    print(f"  {info.get('type','?')}: {info.get('title','?')[:60]}")
                continue
            if expr:
                safe_eval(pipe, expr, expr)
        except (EOFError, KeyboardInterrupt):
            break

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Figma CDP Pipe Explorer")
    parser.add_argument("--probe", action="store_true", help="自动探测")
    args = parser.parse_args()

    # 检查 Figma 是否已在运行
    if subprocess.run(["pgrep", "-f", "Figma\\+EX"], capture_output=True).returncode == 0:
        print("Figma 正在运行。需要关闭当前实例来启动 pipe 模式。")
        respond = input("关闭并重启? [y/N]: ").strip().lower()
        if respond != 'y':
            print("已取消")
            sys.exit(0)
        subprocess.run(["osascript", "-e", 'tell application "Figma+EX" to quit'])
        time.sleep(3)

    proc = launch_figma()
    pipe = DevToolsPipe(proc)
    pipe.start()

    # 等待 Figma 初始化并发送 target 信息
    print("等待 Figma 初始化...")
    time.sleep(5)

    if pipe.proc.poll() is not None:
        print(f"[ERROR] Figma 进程意外退出 (exit code: {pipe.proc.returncode})")
        stderr = pipe.proc.stderr.read().decode('utf-8', errors='replace')
        # 检查 pipe error
        if "Could not write into pipe" in stderr:
            print("[ERROR] DevTools pipe 写入失败 - 可能是 Figma 禁用了 pipe 模式")
        else:
            pipe_errors = [l for l in stderr.split('\n') if 'devtools' in l.lower()]
            if pipe_errors:
                print("[ERROR] Pipe errors:")
                for l in pipe_errors[:5]:
                    print(f"  {l[:200]}")
        sys.exit(1)

    # 获取初始 targets
    print("\n[INFO] 获取可调试目标...")
    pipe.get_targets()

    # 列出所有发现的 targets
    print(f"\n发现 {len(pipe.targets)} 个目标:")
    for tid, info in pipe.targets.items():
        print(f"  [{info.get('type','?')}] {info.get('title','')[:60]}")

    # 找到 figma 编辑器页面
    editor_target = None
    for tid, info in pipe.targets.items():
        url = info.get("url", "")
        ttype = info.get("type", "")
        if ttype == "page" and ("figma.com" in url or "figma" in url.lower()):
            editor_target = tid
            print(f"\n找到编辑器页面: {info.get('title', '')}")

    if not editor_target:
        # 尝试第一个 page 类型
        for tid, info in pipe.targets.items():
            if info.get("type") == "page":
                editor_target = tid
                break

    if editor_target:
        print(f"附加到目标: {editor_target}")
        session_id = pipe.attach_to_target(editor_target)
        if session_id:
            print(f"Session: {session_id[:20]}...")
            pipe._session_id = session_id

    if args.probe:
        probe_environment(pipe)
        probe_editor(pipe)
    else:
        interactive(pipe)

    pipe.stop()
    print("\nDone.")

if __name__ == "__main__":
    main()
