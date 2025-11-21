#!/bin/bash

# =============================================================================
# 监控 Docker 迁移进度
# =============================================================================

CONSOLE_LOG="/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/migration_console.log"
PID_FILE="/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/migration.pid"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Docker 迁移监控"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查进程是否在运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ 迁移进程正在运行 (PID: $PID)"
    else
        echo "⚠️  迁移进程已结束 (PID: $PID)"
    fi
else
    echo "ℹ️  未找到 PID 文件"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 最新日志（最后30行）:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f "$CONSOLE_LOG" ]; then
    tail -30 "$CONSOLE_LOG"
else
    echo "❌ 日志文件不存在: $CONSOLE_LOG"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 提示:"
echo "   实时监控: tail -f $CONSOLE_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

