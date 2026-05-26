#!/bin/bash
# 重启 Figma 并开启 Chrome DevTools Protocol 调试端口
# 用法: ./restart-figma.sh [--port=9222]

PORT=9222

for arg in "$@"; do
    case $arg in
        --port=*) PORT="${arg#*=}" ;;
        *) echo "用法: $0 [--port=9222]"; exit 1 ;;
    esac
done

FIGMA_APP="Figma+EX"

echo "==> 正在关闭 Figma+EX..."
osascript -e "tell application \"$FIGMA_APP\" to quit" 2>/dev/null

# 等待 Figma 完全退出
for i in $(seq 1 15); do
    if ! pgrep -f "$FIGMA_APP" > /dev/null 2>&1; then
        echo "==> Figma 已关闭"
        break
    fi
    sleep 1
done

# 强制 kill 残留进程
pkill -f "Figma" 2>/dev/null
sleep 1

echo "==> 以调试模式启动 Figma (CDP 端口: $PORT)..."
open -a "$FIGMA_APP" --args --remote-debugging-port="$PORT"

echo "==> 等待 Figma 启动..."
for i in $(seq 1 20); do
    if curl -s "http://localhost:$PORT/json" > /dev/null 2>&1; then
        echo "==> CDP 端点就绪: http://localhost:$PORT"
        curl -s "http://localhost:$PORT/json" | python3 -m json.tool 2>/dev/null
        exit 0
    fi
    sleep 1
done

echo "==> 超时: CDP 端点未在 $PORT 端口启动"
echo "==> 可能原因: Figma+EX 的发布版本禁用了 --remote-debugging-port"
exit 1
