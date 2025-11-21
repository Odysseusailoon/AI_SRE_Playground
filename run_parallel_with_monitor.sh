#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 并行测试 + 资源监控 一体化启动脚本
# 监控会在并行测试结束后自动停止
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
cd "$BASE_DIR" || { echo "无法进入项目目录"; exit 1; }

# 日志目录
LOG_DIR="cwy/log/parallel10"
mkdir -p "$LOG_DIR"

# 采样间隔（秒）
SAMPLE_INTERVAL=${1:-2}

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🚀 并行测试 + 资源监控 启动器${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}采样间隔: ${SAMPLE_INTERVAL} 秒${NC}"
echo -e "${YELLOW}日志目录: ${LOG_DIR}/${NC}"
echo ""

# 1. 启动资源监控（后台）
echo -e "${CYAN}▶ 步骤 1/3: 启动资源监控...${NC}"
bash monitor_resources_max.sh "$SAMPLE_INTERVAL" "$LOG_DIR" > /dev/null 2>&1 &
MONITOR_PID=$!

echo -e "${GREEN}   ✓ 监控已启动 (PID: ${MONITOR_PID})${NC}"
sleep 2

# 2. 启动并行测试
echo -e "${CYAN}▶ 步骤 2/3: 启动并行测试 (10个任务)...${NC}"
echo ""

bash parallel_test_4_different_tasks.sh
PARALLEL_EXIT_CODE=$?

echo ""
echo -e "${CYAN}▶ 步骤 3/3: 并行测试已结束，正在停止监控...${NC}"

# 3. 停止监控
if kill -0 $MONITOR_PID 2>/dev/null; then
    kill -INT $MONITOR_PID 2>/dev/null
    sleep 3
    
    # 如果还没停止，强制停止
    if kill -0 $MONITOR_PID 2>/dev/null; then
        kill -9 $MONITOR_PID 2>/dev/null
    fi
    
    echo -e "${GREEN}   ✓ 监控已停止${NC}"
else
    echo -e "${YELLOW}   ⚠ 监控进程已不存在${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 所有任务已完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📁 输出文件位置:${NC}"
echo -e "   日志目录: ${LOG_DIR}/"
echo ""
echo -e "${YELLOW}📊 查看资源统计报告:${NC}"
echo -e "   ${GREEN}cat ${LOG_DIR}/resource_summary_*.txt${NC}"
echo ""
echo -e "${YELLOW}📈 查看CSV数据:${NC}"
echo -e "   ${GREEN}ls -lh ${LOG_DIR}/resource_data_*.csv${NC}"
echo ""
echo -e "${YELLOW}🔍 查看并行测试日志:${NC}"
echo -e "   ${GREEN}cat ${LOG_DIR}/parallel_test_main.log${NC}"
echo ""

# 显示最新的统计报告
LATEST_SUMMARY=$(ls -t ${LOG_DIR}/resource_summary_*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_SUMMARY" ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 资源使用统计摘要:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "$LATEST_SUMMARY"
fi

exit $PARALLEL_EXIT_CODE

