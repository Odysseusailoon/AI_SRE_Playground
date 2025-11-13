#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

while true; do
    clear
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 AIOpsLab 并行任务资源监控${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 显示时间
    echo -e "${BLUE}⏰ 当前时间:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 1. Python任务进程状态
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🐍 Python任务进程 (4个并行任务)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    PYTHON_PROCS=$(ps aux | grep "python.*aiopslab" | grep -v grep | wc -l)
    if [ "$PYTHON_PROCS" -gt 0 ]; then
        printf "%-8s %-6s %-5s %-6s %-10s %s\n" "USER" "PID" "%CPU" "%MEM" "TIME" "COMMAND"
        ps aux | grep "python.*aiopslab" | grep -v grep | awk '{printf "%-8s %-6s %-5s %-6s %-10s %s %s %s\n", $1, $2, $3, $4, $10, $11, $12, $13}'
        echo ""
        echo -e "${GREEN}✅ 运行中的任务数: ${PYTHON_PROCS}${NC}"
    else
        echo -e "${RED}❌ 没有运行中的任务${NC}"
    fi
    echo ""
    
    # 2. Kind集群容器资源使用
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🐳 Kind集群容器资源使用${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 获取所有kind容器的统计信息（不持续流式输出）
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
        $(docker ps --filter "name=kind" --format "{{.Names}}" | tr '\n' ' ') 2>/dev/null
    echo ""
    
    # 3. 任务日志尾部（最新几行）
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📝 任务最新日志 (最后2行)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for cluster in kind kind1 kind2 kind3; do
        LOG_FILE=$(ls -t logs/parallel/task_${cluster}_*.log 2>/dev/null | head -1)
        if [ -n "$LOG_FILE" ]; then
            TASK_NAME=$(basename "$LOG_FILE" .log | sed "s/task_${cluster}_//")
            echo -e "${BLUE}[$cluster - $TASK_NAME]${NC}"
            tail -2 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
            echo ""
        fi
    done
    
    # 4. 系统整体资源
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💻 系统整体资源${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # CPU总体使用率
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "${BLUE}CPU使用率:${NC} ${CPU_USAGE}%"
    
    # 内存使用
    MEM_INFO=$(free -h | grep "Mem:")
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_FREE=$(echo $MEM_INFO | awk '{print $4}')
    MEM_PERCENT=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    echo -e "${BLUE}内存使用:${NC} ${MEM_USED} / ${MEM_TOTAL} (${MEM_PERCENT}%)"
    
    # 磁盘使用
    DISK_INFO=$(df -h / | tail -1)
    DISK_USED=$(echo $DISK_INFO | awk '{print $3}')
    DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
    DISK_PERCENT=$(echo $DISK_INFO | awk '{print $5}')
    echo -e "${BLUE}磁盘使用:${NC} ${DISK_USED} / ${DISK_TOTAL} (${DISK_PERCENT})"
    
    # 负载平均
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    echo -e "${BLUE}负载平均:${NC}${LOAD_AVG}"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🔄 每2秒自动刷新 | 按 Ctrl+C 退出${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    sleep 2
done

