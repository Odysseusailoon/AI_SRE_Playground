#!/bin/bash

# =============================================================================
# 在 kind11 上运行测试任务
# =============================================================================

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
cd "$BASE_DIR" || exit 1

# 确保日志目录存在
mkdir -p cwy/log/test

# kind-test 测试任务
TASK="auth_miss_mongodb-localization-1"
CLUSTER="kind-test"
# MAX_STEPS=30  # 原配置：完整测试
MAX_STEPS=1     # 快速测试：只运行1轮

# 日志文件
LOG_FILE="cwy/log/test/task_${CLUSTER}_${TASK}.log"
POD_LOG="cwy/log/test/task_${CLUSTER}_pods_stages.txt"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Kind-test 测试任务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "集群: $CLUSTER"
echo "任务: $TASK"
echo "最大步数: $MAX_STEPS"
echo "日志: $LOG_FILE"
echo "Pod记录: $POD_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 清空旧的 pod 日志
> "$POD_LOG"

# 激活环境
source ~/miniconda3/bin/activate aiopslab
export PYTHONPATH="$BASE_DIR:${PYTHONPATH}"

# 指定使用 kind11 集群
export AIOPSLAB_CLUSTER="$CLUSTER"

# 禁用代理
unset http_proxy https_proxy all_proxy

# 后台运行 pod 监控脚本
bash "$BASE_DIR/monitor_pods_kind11.sh" "$POD_LOG" &
MONITOR_PID=$!
echo "Pod监控进程: $MONITOR_PID"

# 运行测试任务
echo ""
echo "开始运行测试..."
echo ""

python -u clients/gpt.py --problem "$TASK" --max-steps "$MAX_STEPS" 2>&1 | tee "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[0]}

# 停止监控进程
kill $MONITOR_PID 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 任务完成"
else
    echo "❌ 任务失败 (退出码: $EXIT_CODE)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 日志位置:"
echo "  主日志: $LOG_FILE"
echo "  Pod记录: $POD_LOG"
echo ""

exit $EXIT_CODE

