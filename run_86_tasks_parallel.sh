#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 86任务并行测试脚本 (使用11个Kind集群)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
cd "$BASE_DIR" || { echo -e "${RED}错误: 无法进入项目目录!${NC}"; exit 1; }

# 确保日志目录存在
mkdir -p logs/single

# 可用的集群列表 (只使用4个集群)
CLUSTERS=(kind kind1 kind2 kind3)

# 86个任务列表
TASKS=(
    "revoke_auth_mongodb-detection-1"
    "revoke_auth_mongodb-detection-2"
    "revoke_auth_mongodb-localization-1"
    "revoke_auth_mongodb-localization-2"
    "revoke_auth_mongodb-analysis-1"
    "revoke_auth_mongodb-analysis-2"
    "revoke_auth_mongodb-mitigation-1"
    "revoke_auth_mongodb-mitigation-2"
    "auth_miss_mongodb-detection-1"
    "auth_miss_mongodb-detection-2"
    "auth_miss_mongodb-localization-1"
    "auth_miss_mongodb-localization-2"
    "auth_miss_mongodb-analysis-1"
    "auth_miss_mongodb-analysis-2"
    "auth_miss_mongodb-mitigation-1"
    "auth_miss_mongodb-mitigation-2"
    "user_unregistered_mongodb-detection-1"
    "user_unregistered_mongodb-detection-2"
    "user_unregistered_mongodb-localization-1"
    "user_unregistered_mongodb-localization-2"
    "user_unregistered_mongodb-analysis-1"
    "user_unregistered_mongodb-analysis-2"
    "user_unregistered_mongodb-mitigation-1"
    "user_unregistered_mongodb-mitigation-2"
    "missing_image-detection-1"
    "missing_image-detection-2"
    "missing_image-localization-1"
    "missing_image-localization-2"
    "missing_image-analysis-1"
    "missing_image-analysis-2"
    "missing_image-mitigation-1"
    "missing_image-mitigation-2"
    "container_kill-detection-1"
    "container_kill-detection-2"
    "container_kill-localization-1"
    "container_kill-localization-2"
    "container_kill-analysis-1"
    "container_kill-analysis-2"
    "container_kill-mitigation-1"
    "container_kill-mitigation-2"
    "pod_kill_hotel_res-detection-1"
    "pod_kill_hotel_res-detection-2"
    "pod_kill_hotel_res-localization-1"
    "pod_kill_hotel_res-localization-2"
    "pod_kill_hotel_res-analysis-1"
    "pod_kill_hotel_res-analysis-2"
    "pod_kill_hotel_res-mitigation-1"
    "pod_kill_hotel_res-mitigation-2"
    "pod_failure_hotel_res-detection-1"
    "pod_failure_hotel_res-detection-2"
    "pod_failure_hotel_res-localization-1"
    "pod_failure_hotel_res-localization-2"
    "pod_failure_hotel_res-analysis-1"
    "pod_failure_hotel_res-analysis-2"
    "pod_failure_hotel_res-mitigation-1"
    "pod_failure_hotel_res-mitigation-2"
    "network_delay_hotel_res-detection-1"
    "network_delay_hotel_res-detection-2"
    "network_delay_hotel_res-localization-1"
    "network_delay_hotel_res-localization-2"
    "network_delay_hotel_res-analysis-1"
    "network_delay_hotel_res-analysis-2"
    "network_delay_hotel_res-mitigation-1"
    "network_delay_hotel_res-mitigation-2"
    "network_loss_hotel_res-detection-1"
    "network_loss_hotel_res-detection-2"
    "network_loss_hotel_res-localization-1"
    "network_loss_hotel_res-localization-2"
    "network_loss_hotel_res-analysis-1"
    "network_loss_hotel_res-analysis-2"
    "network_loss_hotel_res-mitigation-1"
    "network_loss_hotel_res-mitigation-2"
    "misconfig_app_hotel_res-detection-1"
    "misconfig_app_hotel_res-detection-2"
    "misconfig_app_hotel_res-localization-1"
    "misconfig_app_hotel_res-localization-2"
    "misconfig_app_hotel_res-analysis-1"
    "misconfig_app_hotel_res-analysis-2"
    "misconfig_app_hotel_res-mitigation-1"
    "misconfig_app_hotel_res-mitigation-2"
    "k8s_target_port-misconfig-detection-1"
    "k8s_target_port-misconfig-detection-2"
    "k8s_target_port-misconfig-localization-1"
    "k8s_target_port-misconfig-localization-2"
    "k8s_target_port-misconfig-analysis-1"
    "k8s_target_port-misconfig-analysis-2"
    "k8s_target_port-misconfig-mitigation-1"
    "k8s_target_port-misconfig-mitigation-2"
)

# 最大步数
MAX_STEPS=30

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 86任务并行测试 (4个Kind集群)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}任务总数: ${#TASKS[@]}${NC}"
echo -e "${YELLOW}集群总数: ${#CLUSTERS[@]}${NC}"
echo -e "${YELLOW}最大步数: ${MAX_STEPS}${NC}"
echo ""

# 清理旧的临时脚本
rm -f /tmp/run_task_*.sh

# 为每个任务创建包装脚本
echo -e "${YELLOW}📝 创建包装脚本...${NC}"
for i in "${!TASKS[@]}"; do
    task="${TASKS[$i]}"
    cluster_idx=$((i % ${#CLUSTERS[@]}))
    cluster="${CLUSTERS[$cluster_idx]}"
    wrapper_script="/tmp/run_task_${i}_$$.sh"
    
    cat > "$wrapper_script" << EOF
#!/bin/bash
# Wrapper script for task: $task on cluster: $cluster

CLUSTER_NAME="$cluster"
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

# 禁用代理（代理有503错误，tiktoken已缓存）
unset http_proxy https_proxy all_proxy

# 使用环境变量指定集群
export AIOPSLAB_CLUSTER="\$CLUSTER_NAME"

# 运行测试（彻底禁用所有缓冲）
export PYTHONUNBUFFERED=1
stdbuf -o0 -e0 python3 -u clients/gpt.py --problem "\$TASK_ID" --max-steps $MAX_STEPS
EXIT_CODE=\$?

exit \$EXIT_CODE
EOF

    chmod +x "$wrapper_script"
done
echo -e "${GREEN}✅ 包装脚本创建完成${NC}"
echo ""

# 启动所有任务
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 启动所有测试任务...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PIDS=()
declare -A CLUSTER_COUNT

for i in "${!TASKS[@]}"; do
    task="${TASKS[$i]}"
    cluster_idx=$((i % ${#CLUSTERS[@]}))
    cluster="${CLUSTERS[$cluster_idx]}"
    wrapper_script="/tmp/run_task_${i}_$$.sh"
    log_file="logs/single/task_${task}_0.log"
    pid_file="logs/single/task_${task}_0.pid"
    
    # 统计每个集群的任务数
    CLUSTER_COUNT[$cluster]=$((${CLUSTER_COUNT[$cluster]:-0} + 1))
    
    echo -e "${YELLOW}[$((i+1))/${#TASKS[@]}]${NC} ${GREEN}[$cluster]${NC} → $task"
    PYTHONUNBUFFERED=1 nohup bash "$wrapper_script" \
        > "$log_file" 2>&1 &
    TASK_PID=$!
    echo $TASK_PID > "$pid_file"
    PIDS+=($TASK_PID)
    
    # 每10个任务暂停一下，避免瞬间启动太多
    if [ $(( (i+1) % 10 )) -eq 0 ]; then
        sleep 1
    fi
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 所有任务已启动！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📊 集群任务分配:${NC}"
for cluster in "${CLUSTERS[@]}"; do
    count=${CLUSTER_COUNT[$cluster]:-0}
    echo -e "  ${GREEN}[$cluster]${NC}: $count 个任务"
done
echo ""
echo -e "${YELLOW}📊 监控命令:${NC}"
echo ""
echo -e "  # 查看所有日志文件"
echo -e "  ${GREEN}ls -lht logs/single/task_*.log | head -20${NC}"
echo ""
echo -e "  # 实时监控某个任务"
echo -e "  ${GREEN}tail -f logs/single/task_revoke_auth_mongodb-detection-1_0.log${NC}"
echo ""
echo -e "  # 统计完成情况"
echo -e "  ${GREEN}grep -l 'Episode completed' logs/single/task_*.log | wc -l${NC}"
echo ""
echo -e "  # 停止所有任务"
echo -e "  ${GREEN}pkill -f 'python3.*gpt.py'${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
