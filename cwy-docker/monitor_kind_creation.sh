#!/bin/bash

# =============================================================================
# 监控 Kind 集群批量创建进度
# =============================================================================

BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
LOG_DIR="$BASE_DIR/logs/docker/kind_creation"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Kind 集群批量创建监控${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 检查进程
echo -e "${BLUE}📊 进程状态:${NC}"
if ps aux | grep "create_kinds_11_to_86.sh" | grep -v grep > /dev/null; then
    echo -e "${GREEN}✅ 创建脚本正在运行${NC}"
    ps aux | grep "create_kinds_11_to_86.sh" | grep -v grep
else
    echo -e "${YELLOW}⚠️  创建脚本未运行${NC}"
fi
echo ""

# 2. 当前集群数量
echo -e "${BLUE}📦 集群数量:${NC}"
TOTAL_CLUSTERS=$(kind get clusters 2>/dev/null | wc -l)
echo "  总计: $TOTAL_CLUSTERS 个集群"
echo "  目标: 87 个集群 (kind0-kind86)"
echo "  进度: $(awk "BEGIN {printf \"%.1f%%\", ($TOTAL_CLUSTERS/87)*100}")"
echo ""

# 3. 最新日志（主日志）
echo -e "${BLUE}📝 最新日志 (最后20行):${NC}"
LATEST_MAIN_LOG=$(ls -t "$LOG_DIR"/batch_creation_*.log 2>/dev/null | head -1)
if [ -f "$LATEST_MAIN_LOG" ]; then
    echo "  日志文件: $LATEST_MAIN_LOG"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tail -20 "$LATEST_MAIN_LOG"
else
    echo "  ⚠️  未找到主日志文件"
fi
echo ""

# 4. 当前正在创建的集群
echo -e "${BLUE}🔧 当前操作:${NC}"
if [ -f "$LATEST_MAIN_LOG" ]; then
    CURRENT_CLUSTER=$(tail -50 "$LATEST_MAIN_LOG" | grep "开始创建集群" | tail -1 | awk '{print $NF}')
    if [ -n "$CURRENT_CLUSTER" ]; then
        echo "  正在创建: $CURRENT_CLUSTER"
        
        # 显示当前集群的步骤
        CURRENT_STEP=$(tail -20 "$LATEST_MAIN_LOG" | grep "步骤" | tail -1)
        if [ -n "$CURRENT_STEP" ]; then
            echo "  当前步骤: $CURRENT_STEP"
        fi
    else
        echo "  状态: 准备中..."
    fi
else
    echo "  状态: 未知"
fi
echo ""

# 5. 统计信息
echo -e "${BLUE}📈 统计信息:${NC}"
if [ -f "$LATEST_MAIN_LOG" ]; then
    SUCCESS_COUNT=$(grep -c "集群.*完成 (耗时:" "$LATEST_MAIN_LOG" 2>/dev/null || echo "0")
    FAILED_COUNT=$(grep -c "集群.*创建失败" "$LATEST_MAIN_LOG" 2>/dev/null || echo "0")
    echo "  ✅ 成功: $SUCCESS_COUNT"
    echo "  ❌ 失败: $FAILED_COUNT"
    REMAINING=$((76 - SUCCESS_COUNT - FAILED_COUNT))
    echo "  ⏳ 待创建: $REMAINING"
    
    # 平均耗时
    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        AVG_TIME=$(grep "集群.*完成 (耗时:" "$LATEST_MAIN_LOG" | awk -F'耗时: ' '{print $2}' | awk -F'秒' '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count}')
        if [ -n "$AVG_TIME" ] && [ "$AVG_TIME" -gt 0 ]; then
            echo "  ⏱️  平均耗时: ${AVG_TIME}秒/集群"
            
            if [ "$REMAINING" -gt 0 ]; then
                EST_MINUTES=$(( (REMAINING * AVG_TIME) / 60 ))
                echo "  📅 预计剩余: ${EST_MINUTES}分钟"
            fi
        fi
    fi
fi
echo ""

# 6. 磁盘使用
echo -e "${BLUE}💾 磁盘使用:${NC}"
df -h /data | tail -1
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "提示: 运行 'bash $(basename $0)' 查看最新状态"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

