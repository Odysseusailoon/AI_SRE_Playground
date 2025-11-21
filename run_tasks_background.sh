#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 后台启动86个任务的包装脚本
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_LOG="$BASE_DIR/logs/single/master_${TIMESTAMP}.log"

mkdir -p "$BASE_DIR/logs/single"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 后台启动86个任务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "主日志: $MASTER_LOG"
echo ""

# 后台运行主脚本
nohup bash "$BASE_DIR/run_86_tasks_parallel.sh" > "$MASTER_LOG" 2>&1 &
MASTER_PID=$!

echo "✅ 主脚本已在后台启动"
echo "   PID: $MASTER_PID"
echo "   日志: $MASTER_LOG"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 监控命令:"
echo ""
echo "  # 查看主脚本日志"
echo "  tail -f $MASTER_LOG"
echo ""
echo "  # 查看任务状态"
echo "  bash logs/single/monitor_tasks.sh"
echo ""
echo "  # 统计运行中的任务"
echo "  pgrep -f 'python3.*gpt.py' | wc -l"
echo ""
echo "  # 停止所有任务"
echo "  pkill -f 'python3.*gpt.py'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

