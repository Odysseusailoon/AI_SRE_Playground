#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🔍 资源监控 + 并行测试运行脚本
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs/parallel"
MONITOR_LOG_DIR="$SCRIPT_DIR/logs/monitor"

# 创建监控日志目录
mkdir -p "$MONITOR_LOG_DIR"

# 日志文件（固定名称，每次运行会覆盖）
RESOURCE_LOG="$MONITOR_LOG_DIR/resource_usage.log"
SUMMARY_LOG="$MONITOR_LOG_DIR/resource_summary.log"
CLUSTER_LOG="$MONITOR_LOG_DIR/cluster_usage.log"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🚀 启动并行测试 + 资源监控${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📊 资源监控函数
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

monitor_resources() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 开始资源监控...${NC}"
    echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$RESOURCE_LOG"
    echo "监控间隔: 10秒" >> "$RESOURCE_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    # 记录初始状态
    echo "【初始系统状态】" >> "$RESOURCE_LOG"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    # CPU信息
    echo "CPU信息:" >> "$RESOURCE_LOG"
    lscpu | grep -E "^CPU\(s\)|^Model name|^Thread|^Core" >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    # 内存信息
    echo "内存信息:" >> "$RESOURCE_LOG"
    free -h >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    # 磁盘信息
    echo "磁盘信息:" >> "$RESOURCE_LOG"
    df -h / >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$RESOURCE_LOG"
    echo "" >> "$RESOURCE_LOG"
    
    # 持续监控循环
    COUNTER=0
    while true; do
        COUNTER=$((COUNTER + 1))
        CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo "【监控记录 #$COUNTER】 $CURRENT_TIME" >> "$RESOURCE_LOG"
        echo "" >> "$RESOURCE_LOG"
        
        # 1. CPU负载
        LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
        echo "CPU负载 (1/5/15分钟): $LOAD_AVG" >> "$RESOURCE_LOG"
        
        # 2. CPU使用率（top）
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        echo "CPU使用率: ${CPU_USAGE}%" >> "$RESOURCE_LOG"
        
        # 3. 内存使用
        MEM_INFO=$(free -h | grep Mem | awk '{print "总计:"$2" 已用:"$3" 空闲:"$4" 使用率:"$3"/"$2}')
        echo "内存: $MEM_INFO" >> "$RESOURCE_LOG"
        
        # 4. 磁盘使用
        DISK_INFO=$(df -h / | tail -1 | awk '{print "总计:"$2" 已用:"$3" 空闲:"$4" 使用率:"$5}')
        echo "磁盘: $DISK_INFO" >> "$RESOURCE_LOG"
        
        # 5. Python进程数
        PYTHON_COUNT=$(ps aux | grep -E 'python3.*gpt.py' | grep -v grep | wc -l)
        echo "Python测试进程数: $PYTHON_COUNT" >> "$RESOURCE_LOG"
        
        # 6. Docker容器数
        DOCKER_COUNT=$(docker ps --format '{{.Names}}' | wc -l)
        echo "Docker容器数: $DOCKER_COUNT" >> "$RESOURCE_LOG"
        
        # 7. Top 5 CPU进程
        echo "" >> "$RESOURCE_LOG"
        echo "Top 5 CPU进程:" >> "$RESOURCE_LOG"
        ps aux --sort=-%cpu | head -6 | tail -5 >> "$RESOURCE_LOG"
        
        # 8. Top 5 内存进程
        echo "" >> "$RESOURCE_LOG"
        echo "Top 5 内存进程:" >> "$RESOURCE_LOG"
        ps aux --sort=-%mem | head -6 | tail -5 >> "$RESOURCE_LOG"
        
        echo "" >> "$RESOURCE_LOG"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$RESOURCE_LOG"
        echo "" >> "$RESOURCE_LOG"
        
        # 检查测试是否还在运行
        if [ $PYTHON_COUNT -eq 0 ] && [ $COUNTER -gt 5 ]; then
            echo "检测到所有测试已完成，停止监控..." >> "$RESOURCE_LOG"
            break
        fi
        
        sleep 10
    done
    
    echo "监控结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESOURCE_LOG"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📊 集群级别监控
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

monitor_clusters() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 开始集群监控...${NC}"
    echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$CLUSTER_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$CLUSTER_LOG"
    echo "" >> "$CLUSTER_LOG"
    
    COUNTER=0
    while true; do
        COUNTER=$((COUNTER + 1))
        CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo "【集群监控 #$COUNTER】 $CURRENT_TIME" >> "$CLUSTER_LOG"
        echo "" >> "$CLUSTER_LOG"
        
        # 监控每个集群
        for i in {1..10}; do
            CLUSTER="kind$i"
            echo "━━━ $CLUSTER ━━━" >> "$CLUSTER_LOG"
            
            # 检查集群是否存在
            if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
                echo "状态: 集群不存在" >> "$CLUSTER_LOG"
                echo "" >> "$CLUSTER_LOG"
                continue
            fi
            
            # Pod数量
            POD_COUNT=$(kubectl get pods -n default --context kind-${CLUSTER} 2>/dev/null | grep -v NAME | wc -l)
            RUNNING_PODS=$(kubectl get pods -n default --context kind-${CLUSTER} 2>/dev/null | grep Running | wc -l)
            echo "Pod数量: $RUNNING_PODS/$POD_COUNT Running" >> "$CLUSTER_LOG"
            
            # 节点资源使用
            NODE_INFO=$(kubectl top node --context kind-${CLUSTER} 2>/dev/null | tail -1)
            if [ -n "$NODE_INFO" ]; then
                echo "节点资源: $NODE_INFO" >> "$CLUSTER_LOG"
            fi
            
            # Docker容器资源（该集群的control-plane）
            CONTAINER_NAME="${CLUSTER}-control-plane"
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                STATS=$(docker stats --no-stream --format "CPU:{{.CPUPerc}} MEM:{{.MemUsage}}" $CONTAINER_NAME 2>/dev/null)
                echo "容器资源: $STATS" >> "$CLUSTER_LOG"
            fi
            
            echo "" >> "$CLUSTER_LOG"
        done
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$CLUSTER_LOG"
        echo "" >> "$CLUSTER_LOG"
        
        # 检查测试是否还在运行
        PYTHON_COUNT=$(ps aux | grep -E 'python3.*gpt.py' | grep -v grep | wc -l)
        if [ $PYTHON_COUNT -eq 0 ] && [ $COUNTER -gt 5 ]; then
            echo "检测到所有测试已完成，停止集群监控..." >> "$CLUSTER_LOG"
            break
        fi
        
        sleep 30  # 集群监控间隔30秒
    done
    
    echo "集群监控结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$CLUSTER_LOG"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📈 生成资源使用报告
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

generate_summary() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 生成资源使用报告...${NC}"
    
    cat > "$SUMMARY_LOG" << 'SUMMARY_EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 资源使用分析报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY_EOF

    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$SUMMARY_LOG"
    echo "" >> "$SUMMARY_LOG"
    
    # 从资源日志中提取统计数据
    if [ -f "$RESOURCE_LOG" ]; then
        echo "【CPU负载统计】" >> "$SUMMARY_LOG"
        grep "CPU负载" "$RESOURCE_LOG" | tail -20 >> "$SUMMARY_LOG"
        echo "" >> "$SUMMARY_LOG"
        
        echo "【内存使用统计】" >> "$SUMMARY_LOG"
        grep "内存:" "$RESOURCE_LOG" | tail -20 >> "$SUMMARY_LOG"
        echo "" >> "$SUMMARY_LOG"
        
        echo "【磁盘使用统计】" >> "$SUMMARY_LOG"
        grep "磁盘:" "$RESOURCE_LOG" | tail -20 >> "$SUMMARY_LOG"
        echo "" >> "$SUMMARY_LOG"
        
        echo "【Python进程数统计】" >> "$SUMMARY_LOG"
        grep "Python测试进程数:" "$RESOURCE_LOG" | tail -20 >> "$SUMMARY_LOG"
        echo "" >> "$SUMMARY_LOG"
    fi
    
    # 计算峰值
    echo "【资源峰值】" >> "$SUMMARY_LOG"
    
    # CPU负载峰值
    MAX_LOAD=$(grep "CPU负载" "$RESOURCE_LOG" | awk -F': ' '{print $2}' | awk -F',' '{print $1}' | sort -n | tail -1)
    echo "CPU负载峰值 (1分钟): $MAX_LOAD" >> "$SUMMARY_LOG"
    
    # 内存峰值（需要解析）
    echo "内存峰值: (需手动分析)" >> "$SUMMARY_LOG"
    
    # 磁盘峰值
    MAX_DISK=$(grep "磁盘:" "$RESOURCE_LOG" | awk -F'已用:' '{print $2}' | awk '{print $1}' | sort -h | tail -1)
    echo "磁盘使用峰值: $MAX_DISK" >> "$SUMMARY_LOG"
    
    echo "" >> "$SUMMARY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$SUMMARY_LOG"
    
    # 任务完成情况
    echo "" >> "$SUMMARY_LOG"
    echo "【任务完成情况】" >> "$SUMMARY_LOG"
    for i in {1..10}; do
        TASK_LOG="$LOG_DIR/task_kind${i}_*.log"
        if ls $TASK_LOG 1> /dev/null 2>&1; then
            LATEST_LOG=$(ls -t $TASK_LOG | head -1)
            if grep -q "✅ 任务执行成功" "$LATEST_LOG" 2>/dev/null; then
                echo "kind$i: ✅ 成功" >> "$SUMMARY_LOG"
            elif grep -q "❌ 任务执行失败" "$LATEST_LOG" 2>/dev/null; then
                echo "kind$i: ❌ 失败" >> "$SUMMARY_LOG"
            else
                echo "kind$i: ⏸️  未完成" >> "$SUMMARY_LOG"
            fi
        else
            echo "kind$i: ❓ 无日志" >> "$SUMMARY_LOG"
        fi
    done
    
    echo "" >> "$SUMMARY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$SUMMARY_LOG"
    echo "详细日志:" >> "$SUMMARY_LOG"
    echo "  - 资源监控: $RESOURCE_LOG" >> "$SUMMARY_LOG"
    echo "  - 集群监控: $CLUSTER_LOG" >> "$SUMMARY_LOG"
    echo "  - 任务日志: $LOG_DIR/" >> "$SUMMARY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$SUMMARY_LOG"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🚀 主流程
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 1. 启动资源监控（后台）
monitor_resources &
MONITOR_PID=$!
echo -e "${GREEN}✅ 资源监控已启动 (PID: $MONITOR_PID)${NC}"

# 2. 启动集群监控（后台）
monitor_clusters &
CLUSTER_MONITOR_PID=$!
echo -e "${GREEN}✅ 集群监控已启动 (PID: $CLUSTER_MONITOR_PID)${NC}"

# 3. 启动4个并行测试
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🚀 启动4个并行测试...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd "$SCRIPT_DIR"
bash parallel_test_4_different_tasks.sh

# 4. 等待监控进程结束
echo -e "${YELLOW}等待监控进程结束...${NC}"
wait $MONITOR_PID
wait $CLUSTER_MONITOR_PID

# 5. 生成报告
generate_summary

# 6. 显示报告
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📊 资源使用报告${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat "$SUMMARY_LOG"

echo ""
echo -e "${GREEN}✅ 所有任务完成！${NC}"
echo -e "${YELLOW}日志文件位置:${NC}"
echo -e "  📊 资源监控: ${CYAN}$RESOURCE_LOG${NC}"
echo -e "  🔧 集群监控: ${CYAN}$CLUSTER_LOG${NC}"
echo -e "  📈 汇总报告: ${CYAN}$SUMMARY_LOG${NC}"
echo -e "  📝 任务日志: ${CYAN}$LOG_DIR/${NC}"

