#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Kind1-34 并行测试 (Social Network 25个任务 + Hotel Reservation 9个任务，30轮完整测试)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
cd "$BASE_DIR" || { echo -e "${RED}错误: 无法进入项目目录!${NC}"; exit 1; }

# 确保日志目录存在
LOG_DIR="cwy/log/parallel34"
mkdir -p "$LOG_DIR"

# 主日志文件
MAIN_LOG="$LOG_DIR/parallel_test_main.log"

# 定义集群和任务映射 (kind1-kind25: Social Network, kind26-kind34: Hotel Reservation)
declare -A CLUSTER_TASKS=(
    # Social Network (25个任务)
    ["kind1"]="k8s_target_port-misconfig-detection-1"
    ["kind2"]="k8s_target_port-misconfig-detection-2"
    ["kind3"]="k8s_target_port-misconfig-detection-3"
    ["kind4"]="auth_miss_mongodb-detection-1"
    ["kind5"]="scale_pod_zero_social_net-detection-1"
    ["kind6"]="assign_to_non_existent_node_social_net-detection-1"
    ["kind7"]="noop_detection_social_network-1"
    ["kind8"]="k8s_target_port-misconfig-localization-1"
    ["kind9"]="k8s_target_port-misconfig-localization-2"
    ["kind10"]="k8s_target_port-misconfig-localization-3"
    ["kind11"]="auth_miss_mongodb-localization-1"
    ["kind12"]="scale_pod_zero_social_net-localization-1"
    ["kind13"]="assign_to_non_existent_node_social_net-localization-1"
    ["kind14"]="k8s_target_port-misconfig-analysis-1"
    ["kind15"]="k8s_target_port-misconfig-analysis-2"
    ["kind16"]="k8s_target_port-misconfig-analysis-3"
    ["kind17"]="auth_miss_mongodb-analysis-1"
    ["kind18"]="scale_pod_zero_social_net-analysis-1"
    ["kind19"]="assign_to_non_existent_node_social_net-analysis-1"
    ["kind20"]="k8s_target_port-misconfig-mitigation-1"
    ["kind21"]="k8s_target_port-misconfig-mitigation-2"
    ["kind22"]="k8s_target_port-misconfig-mitigation-3"
    ["kind23"]="auth_miss_mongodb-mitigation-1"
    ["kind24"]="scale_pod_zero_social_net-mitigation-1"
    ["kind25"]="assign_to_non_existent_node_social_net-mitigation-1"
    # Hotel Reservation (前9个任务)
    ["kind26"]="revoke_auth_mongodb-detection-1"
    ["kind27"]="revoke_auth_mongodb-detection-2"
    ["kind28"]="user_unregistered_mongodb-detection-1"
    ["kind29"]="user_unregistered_mongodb-detection-2"
    ["kind30"]="misconfig_app_hotel_res-detection-1"
    ["kind31"]="container_kill-detection"
    ["kind32"]="pod_failure_hotel_res-detection-1"
    ["kind33"]="pod_kill_hotel_res-detection-1"
    ["kind34"]="network_loss_hotel_res-detection-1"
)

# 最大步数（完整测试）
MAX_STEPS=30

# 开始写主日志
{
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Kind1-34 并行测试 (Social Network 25个任务 + Hotel Reservation 9个任务，30轮完整测试)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏰ 开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "📁 日志目录: $LOG_DIR"
echo "🔢 测试轮数: $MAX_STEPS"
echo ""
} > "$MAIN_LOG"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 Kind1-34 并行测试 (30轮完整测试)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}任务配置:${NC}"
{
echo "任务配置:"
# 遍历 kind1-kind34
for cluster in kind{1..34}; do
    task="${CLUSTER_TASKS[$cluster]}"
    echo -e "  ${GREEN}[$cluster]${NC} → $task"
    echo "  [$cluster] → $task" >> "$MAIN_LOG"
done
echo ""
echo "" >> "$MAIN_LOG"
}

# 为每个集群创建包装脚本
for cluster in kind{1..34}; do
    task="${CLUSTER_TASKS[$cluster]}"
    wrapper_script="/tmp/run_on_${cluster}_$$.sh"
    
    cat > "$wrapper_script" << EOF
#!/bin/bash
# Wrapper script for cluster: $cluster, task: $task

CLUSTER_NAME="$cluster"
CONTEXT="kind-$cluster"
TASK_ID="$task"
BASE_DIR="$BASE_DIR"

cd "\$BASE_DIR"

# 激活 conda 环境
if [ -f ~/miniconda3/etc/profile.d/conda.sh ]; then
    source ~/miniconda3/etc/profile.d/conda.sh
elif [ -f ~/anaconda3/etc/profile.d/conda.sh ]; then
    source ~/anaconda3/etc/profile.d/conda.sh
fi
conda activate aiopslab 2>/dev/null || true

export PYTHONPATH="\$BASE_DIR:\${PYTHONPATH}"

# 使用环境变量指定集群（无需修改 config.yml）
export AIOPSLAB_CLUSTER="\$CLUSTER_NAME"

# 运行测试（彻底禁用所有缓冲）
export PYTHONUNBUFFERED=1
stdbuf -o0 -e0 python3 -u clients/gpt.py --problem "\$TASK_ID" --max-steps $MAX_STEPS
EXIT_CODE=\$?

exit \$EXIT_CODE
EOF

    chmod +x "$wrapper_script"
done

# 启动所有任务
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 启动所有测试任务...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PIDS=()

# 启动 kind1-kind34 的测试任务
for cluster in kind{1..34}; do
    task="${CLUSTER_TASKS[$cluster]}"
    wrapper_script="/tmp/run_on_${cluster}_$$.sh"
    log_file="$LOG_DIR/task_${cluster}_${task}.log"
    pid_file="$LOG_DIR/task_${cluster}_${task}.pid"
    
    echo -e "${YELLOW}🧪 启动任务: ${GREEN}[$cluster]${NC} → $task${NC}"
    echo "🧪 启动任务: [$cluster] → $task (PID将在下面)" >> "$MAIN_LOG"
    
    PYTHONUNBUFFERED=1 nohup bash "$wrapper_script" \
        > "$log_file" 2>&1 &
    TASK_PID=$!
    echo $TASK_PID > "$pid_file"
    PIDS+=($TASK_PID)
    echo -e "   ${GREEN}✅ PID: ${TASK_PID}${NC}"
    echo "   ✅ PID: $TASK_PID | 日志: $log_file" >> "$MAIN_LOG"
done

echo ""

# 记录到主日志
{
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 所有任务已启动！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "运行的进程: ${PIDS[@]}"
echo "⏰ 启动完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
} >> "$MAIN_LOG"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 所有任务已启动！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📊 监控命令:${NC}"
echo ""
echo -e "  # 查看主日志"
echo -e "  ${GREEN}tail -f $MAIN_LOG${NC}"
echo ""
echo -e "  # 实时监控所有任务"
echo -e "  ${GREEN}watch -n 2 'tail -n 5 $LOG_DIR/*.log'${NC}"
echo ""
echo -e "  # 查看单个任务日志 (kind1-kind34)"
for cluster in kind{1..34}; do
    task="${CLUSTER_TASKS[$cluster]}"
    echo -e "  ${GREEN}tail -f $LOG_DIR/task_${cluster}_${task}.log${NC}"
done
echo ""
echo -e "  # 检查进程状态"
echo -e "  ${GREEN}ps -p ${PIDS[@]} -o pid,etime,cmd${NC}"
echo ""
echo -e "  # 停止所有任务"
echo -e "  ${GREEN}pkill -f 'python3.*gpt.py'${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

