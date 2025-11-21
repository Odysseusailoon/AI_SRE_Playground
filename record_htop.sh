#!/bin/bash

# 记录htop输出到日志
LOG_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo/logs/monitor"
HTOP_LOG="$LOG_DIR/htop_detailed.log"

echo "开始记录htop详细信息: $(date)" > "$HTOP_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$HTOP_LOG"
echo "" >> "$HTOP_LOG"

# 每30秒记录一次htop快照
COUNTER=1
while true; do
    echo "" >> "$HTOP_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$HTOP_LOG"
    echo "【快照 #$COUNTER】 $(date '+%Y-%m-%d %H:%M:%S')" >> "$HTOP_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$HTOP_LOG"
    echo "" >> "$HTOP_LOG"
    
    # 使用top命令代替htop（更适合脚本）
    # 显示所有CPU核心和前50个进程
    top -b -n 1 -o %CPU | head -60 >> "$HTOP_LOG"
    
    echo "" >> "$HTOP_LOG"
    echo "【Docker容器资源】" >> "$HTOP_LOG"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep kind >> "$HTOP_LOG"
    
    echo "" >> "$HTOP_LOG"
    echo "【系统资源汇总】" >> "$HTOP_LOG"
    echo "CPU负载: $(uptime | awk -F'load average:' '{print $2}')" >> "$HTOP_LOG"
    echo "内存: $(free -h | grep Mem | awk '{print "已用:"$3" / 总计:"$2" (可用:"$7")"}')" >> "$HTOP_LOG"
    echo "磁盘: $(df -h / | tail -1 | awk '{print "已用:"$3" / 总计:"$2" (使用率:"$5")"}')" >> "$HTOP_LOG"
    
    COUNTER=$((COUNTER + 1))
    sleep 30
done
