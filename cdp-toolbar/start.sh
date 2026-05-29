#!/bin/bash
# FigmaCDPToolbar 启动脚本
cd "$(dirname "$0")"
swift build -q 2>&1 | tail -5
.build/debug/FigmaCDPToolbar &
echo "FigmaCDPToolbar 已启动 (PID: $!)"
