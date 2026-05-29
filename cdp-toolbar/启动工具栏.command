#!/bin/bash
cd "$(dirname "$0")"
swift build -q 2>/dev/null
.build/debug/FigmaCDPToolbar &
echo "FigmaCDPToolbar 已启动 · 关闭此窗口不影响程序运行"
echo "如需停止: pkill FigmaCDPToolbar"
sleep 2
