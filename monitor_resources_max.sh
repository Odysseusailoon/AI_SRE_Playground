#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 并行测试资源监控脚本 - 记录最大CPU和内存使用
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
SAMPLE_INTERVAL=${1:-2}  # 采样间隔（秒），默认2秒
LOG_DIR=${2:-"cwy/log"}  # 日志目录，默认 cwy/log
mkdir -p "$LOG_DIR"

# 日志文件
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MONITOR_LOG="$LOG_DIR/resource_monitor_${TIMESTAMP}.log"
SUMMARY_FILE="$LOG_DIR/resource_summary_${TIMESTAMP}.txt"
CSV_FILE="$LOG_DIR/resource_data_${TIMESTAMP}.csv"

# 初始化最大值
MAX_CPU_PERCENT=0
MAX_CPU_CORES=0
MAX_MEM_USED_GB=0
MAX_MEM_PERCENT=0
MAX_PYTHON_PROCESSES=0
MAX_DOCKER_CONTAINERS=0
MAX_LOAD_AVG=0

# 记录峰值时间
PEAK_CPU_TIME=""
PEAK_MEM_TIME=""

# 计数器
SAMPLE_COUNT=0

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔍 资源监控脚本启动${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}采样间隔: ${SAMPLE_INTERVAL} 秒${NC}"
echo -e "${YELLOW}日志目录: ${LOG_DIR}/${NC}"
echo -e "${YELLOW}监控日志: ${MONITOR_LOG}${NC}"
echo -e "${YELLOW}统计报告: ${SUMMARY_FILE}${NC}"
echo -e "${YELLOW}CSV数据: ${CSV_FILE}${NC}"
echo ""
echo -e "${CYAN}按 Ctrl+C 停止监控并生成报告${NC}"
echo ""

# 写入CSV表头
echo "Timestamp,CPU_Percent,CPU_Cores_Used,Mem_Used_GB,Mem_Percent,Python_Processes,Docker_Containers,Load_1min,Load_5min,Load_15min" > "$CSV_FILE"

# 开始记录
{
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "资源监控日志"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "采样间隔: ${SAMPLE_INTERVAL}秒"
echo ""
} > "$MONITOR_LOG"

# 清理函数
cleanup() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⏹️  停止监控，生成统计报告...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 生成统计报告
    generate_report
    
    exit 0
}

# 捕获 Ctrl+C
trap cleanup SIGINT SIGTERM

# 生成报告函数
generate_report() {
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local total_cores=$(nproc)
    
    # 生成详细报告
    {
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📊 资源使用统计报告"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "⏰ 监控时间范围"
        echo "   开始: $(head -4 "$MONITOR_LOG" | tail -1 | cut -d: -f2-)"
        echo "   结束: $end_time"
        echo "   采样次数: $SAMPLE_COUNT 次"
        echo "   采样间隔: ${SAMPLE_INTERVAL} 秒"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🖥️  CPU 使用情况"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   系统总核心数: $total_cores 核"
        echo "   最大CPU使用率: ${MAX_CPU_PERCENT}%"
        echo "   最大CPU核心数: ${MAX_CPU_CORES} 核 (相当于 ${MAX_CPU_PERCENT}% 使用率)"
        echo "   峰值时间: ${PEAK_CPU_TIME}"
        echo "   最大系统负载 (1分钟): ${MAX_LOAD_AVG}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "💾 内存使用情况"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 获取总内存
        local total_mem_gb=$(free -g | awk '/^Mem:/ {print $2}')
        
        echo "   系统总内存: ${total_mem_gb} GB"
        echo "   最大内存使用: ${MAX_MEM_USED_GB} GB"
        echo "   最大内存使用率: ${MAX_MEM_PERCENT}%"
        echo "   峰值时间: ${PEAK_MEM_TIME}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🐍 进程统计"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   最大Python进程数: ${MAX_PYTHON_PROCESSES}"
        echo "   最大Docker容器数: ${MAX_DOCKER_CONTAINERS}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📈 资源需求建议"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 计算推荐值（加20%余量）
        local rec_cpu=$(echo "$MAX_CPU_CORES * 1.2" | bc | awk '{printf "%.0f", $1}')
        local rec_mem=$(echo "$MAX_MEM_USED_GB * 1.2" | bc | awk '{printf "%.0f", $1}')
        
        echo "   推荐CPU核心数: ${rec_cpu} 核 (峰值 + 20% 余量)"
        echo "   推荐内存大小: ${rec_mem} GB (峰值 + 20% 余量)"
        echo ""
        echo "   当前配置充足性:"
        if (( $(echo "$total_cores >= $rec_cpu" | bc -l) )); then
            echo "   ✅ CPU: 充足 (当前 ${total_cores} 核 >= 推荐 ${rec_cpu} 核)"
        else
            echo "   ⚠️  CPU: 不足 (当前 ${total_cores} 核 < 推荐 ${rec_cpu} 核)"
        fi
        
        if (( $(echo "$total_mem_gb >= $rec_mem" | bc -l) )); then
            echo "   ✅ 内存: 充足 (当前 ${total_mem_gb} GB >= 推荐 ${rec_mem} GB)"
        else
            echo "   ⚠️  内存: 不足 (当前 ${total_mem_gb} GB < 推荐 ${rec_mem} GB)"
        fi
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📁 数据文件"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   详细日志: $MONITOR_LOG"
        echo "   CSV数据: $CSV_FILE"
        echo "   统计报告: $SUMMARY_FILE"
        echo ""
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } | tee "$SUMMARY_FILE"
    
    # 在终端显示彩色版本
    echo ""
    echo -e "${GREEN}✅ 统计报告已生成: ${SUMMARY_FILE}${NC}"
    echo -e "${GREEN}✅ CSV数据已保存: ${CSV_FILE}${NC}"
    echo ""
}

# 主监控循环
while true; do
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 1. 获取CPU使用率（整体）
    # 使用 top 获取空闲CPU，然后计算使用率
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1)
    CPU_PERCENT=$(echo "100 - $CPU_IDLE" | bc | awk '{printf "%.1f", $1}')
    
    # 计算实际使用的核心数
    TOTAL_CORES=$(nproc)
    CPU_CORES_USED=$(echo "$CPU_PERCENT / 100 * $TOTAL_CORES" | bc -l | awk '{printf "%.2f", $1}')
    
    # 2. 获取内存使用情况
    MEM_INFO=$(free -g | grep "Mem:")
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_PERCENT=$(echo "scale=1; $MEM_USED * 100 / $MEM_TOTAL" | bc)
    
    # 3. 获取系统负载
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    LOAD_5MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | tr -d ',')
    LOAD_15MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}')
    
    # 4. 统计Python进程数
    PYTHON_PROCS=$(ps aux | grep "python3.*gpt.py" | grep -v grep | wc -l)
    
    # 5. 统计Docker容器数
    DOCKER_CONTAINERS=$(docker ps -q | wc -l)
    
    # 更新最大值
    if (( $(echo "$CPU_PERCENT > $MAX_CPU_PERCENT" | bc -l) )); then
        MAX_CPU_PERCENT=$CPU_PERCENT
        MAX_CPU_CORES=$CPU_CORES_USED
        PEAK_CPU_TIME=$CURRENT_TIME
    fi
    
    if (( $(echo "$MEM_USED > $MAX_MEM_USED_GB" | bc -l) )); then
        MAX_MEM_USED_GB=$MEM_USED
        MAX_MEM_PERCENT=$MEM_PERCENT
        PEAK_MEM_TIME=$CURRENT_TIME
    fi
    
    if (( PYTHON_PROCS > MAX_PYTHON_PROCESSES )); then
        MAX_PYTHON_PROCESSES=$PYTHON_PROCS
    fi
    
    if (( DOCKER_CONTAINERS > MAX_DOCKER_CONTAINERS )); then
        MAX_DOCKER_CONTAINERS=$DOCKER_CONTAINERS
    fi
    
    if (( $(echo "$LOAD_AVG > $MAX_LOAD_AVG" | bc -l) )); then
        MAX_LOAD_AVG=$LOAD_AVG
    fi
    
    # 记录到日志
    {
        echo "[$CURRENT_TIME] Sample #$SAMPLE_COUNT"
        echo "  CPU: ${CPU_PERCENT}% (${CPU_CORES_USED} cores)"
        echo "  MEM: ${MEM_USED}GB / ${MEM_TOTAL}GB (${MEM_PERCENT}%)"
        echo "  Load: ${LOAD_AVG}, ${LOAD_5MIN}, ${LOAD_15MIN}"
        echo "  Python Processes: $PYTHON_PROCS"
        echo "  Docker Containers: $DOCKER_CONTAINERS"
        echo ""
    } >> "$MONITOR_LOG"
    
    # 写入CSV
    echo "${CURRENT_TIME},${CPU_PERCENT},${CPU_CORES_USED},${MEM_USED},${MEM_PERCENT},${PYTHON_PROCS},${DOCKER_CONTAINERS},${LOAD_AVG},${LOAD_5MIN},${LOAD_15MIN}" >> "$CSV_FILE"
    
    # 实时显示（覆盖上一行）
    printf "\r${CYAN}[%s]${NC} CPU: ${YELLOW}%6.1f%%${NC} (${GREEN}%5.2f${NC} cores) | MEM: ${YELLOW}%4dGB${NC} (${GREEN}%5.1f%%${NC}) | Load: ${YELLOW}%6.2f${NC} | Py: ${BLUE}%2d${NC} | Docker: ${BLUE}%3d${NC} | Samples: ${CYAN}%d${NC}" \
        "$CURRENT_TIME" "$CPU_PERCENT" "$CPU_CORES_USED" "$MEM_USED" "$MEM_PERCENT" "$LOAD_AVG" "$PYTHON_PROCS" "$DOCKER_CONTAINERS" "$SAMPLE_COUNT"
    
    # 等待下一次采样
    sleep $SAMPLE_INTERVAL
done

