#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4集群4任务并行测试脚本
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
cd "$BASE_DIR" || { echo -e "${RED}错误: 无法进入项目目录!${NC}"; exit 1; }

# 确保日志目录存在
mkdir -p logs/parallel

# 定义集群和任务映射
declare -A CLUSTER_TASKS=(
    ["kind"]="pod_failure_hotel_res-detection-1"
    ["kind1"]="network_loss_hotel_res-localization-1"
    ["kind2"]="container_kill-analysis-1"
    ["kind3"]="pod_kill_hotel_res-mitigation-1"
)

# 最大步数
MAX_STEPS=10

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 4集群4任务并行测试${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}任务配置:${NC}"
for cluster in kind kind1 kind2 kind3; do
    task="${CLUSTER_TASKS[$cluster]}"
    echo -e "  ${GREEN}[$cluster]${NC} → $task"
done
echo ""

# 为每个集群创建包装脚本
for cluster in kind kind1 kind2 kind3; do
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

for cluster in kind kind1 kind2 kind3; do
    task="${CLUSTER_TASKS[$cluster]}"
    wrapper_script="/tmp/run_on_${cluster}_$$.sh"
    log_file="logs/parallel/task_${cluster}_${task}.log"
    pid_file="logs/parallel/task_${cluster}_${task}.pid"
    
    echo -e "${YELLOW}🧪 启动任务: ${GREEN}[$cluster]${NC} → $task${NC}"
    PYTHONUNBUFFERED=1 nohup bash "$wrapper_script" \
        > "$log_file" 2>&1 &
    TASK_PID=$!
    echo $TASK_PID > "$pid_file"
    PIDS+=($TASK_PID)
    echo -e "   ${GREEN}✅ PID: ${TASK_PID}${NC}"
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 所有任务已启动！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📊 监控命令:${NC}"
echo ""
echo -e "  # 实时监控所有任务"
echo -e "  ${GREEN}watch -n 2 'tail -n 5 logs/parallel/*.log'${NC}"
echo ""
echo -e "  # 查看单个任务日志"
for cluster in kind kind1 kind2 kind3; do
    task="${CLUSTER_TASKS[$cluster]}"
    echo -e "  ${GREEN}tail -f logs/parallel/task_${cluster}_${task}.log${NC}"
done
echo ""
echo -e "  # 检查进程状态"
echo -e "  ${GREEN}ps -p ${PIDS[@]} -o pid,etime,cmd${NC}"
echo ""
echo -e "  # 停止所有任务"
echo -e "  ${GREEN}pkill -f 'python3.*gpt.py'${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

