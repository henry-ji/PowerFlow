#!/bin/zsh
# 构建并在菜单栏启动 Power Flow
cd "$(dirname "$0")" || exit 1
swift build -c release || exit 1
pkill -f 'PowerFlowApp' 2>/dev/null
pkill -f 'PowerFlow.app/Contents/MacOS/PowerFlow' 2>/dev/null
sleep 0.5
nohup .build/release/PowerFlowApp >/tmp/powerflow.log 2>&1 &
echo "Power Flow 已在菜单栏启动（闪电图标），点击图标查看流量图。"
