#!/bin/bash
# 批量清理 kind11-20 中不断崩溃的应用，以降低 tw_sock 压力
# 这些应用在任务启动时会自动重新部署

set -e

# 目标集群列表
CLUSTERS=(kind11 kind12 kind13 kind14 kind15 kind16 kind17 kind18 kind19 kind20)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 批量清理 kind11-20 中崩溃的应用"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 清理函数
cleanup_cluster() {
    local CLUSTER=$1
    echo "━━━ 处理 ${CLUSTER} ━━━"
    
    # 检查集群是否运行
    if ! docker ps --format "{{.Names}}" | grep -q "^${CLUSTER}-control-plane$"; then
        echo "   ⚠️  集群 ${CLUSTER} 未运行，跳过"
        return
    fi
    
    # 1. 删除 Chaos Mesh
    echo "   🗑️  删除 Chaos Mesh..."
    docker exec ${CLUSTER}-control-plane kubectl delete namespace chaos-mesh --grace-period=0 --force 2>/dev/null || echo "      (已不存在)"
    
    # 2. 删除 Prometheus
    echo "   🗑️  删除 Prometheus..."
    docker exec ${CLUSTER}-control-plane kubectl delete namespace observe --grace-period=0 --force 2>/dev/null || echo "      (已不存在)"
    
    # 3. 删除微服务应用
    echo "   🗑️  删除微服务应用..."
    docker exec ${CLUSTER}-control-plane kubectl delete namespace test-hotel-reservation --grace-period=0 --force 2>/dev/null || true
    docker exec ${CLUSTER}-control-plane kubectl delete namespace social-network --grace-period=0 --force 2>/dev/null || true
    docker exec ${CLUSTER}-control-plane kubectl delete namespace otel-demo --grace-period=0 --force 2>/dev/null || true
    
    # 4. 检查 tw_sock 状态
    echo "   📊 tw_sock 状态："
    docker exec ${CLUSTER}-control-plane cat /proc/slabinfo 2>/dev/null | grep tw_sock_TCP | \
      awk '{printf "      %s: %d / %d (%.1f%%)\n", $1, $2, $3, $2*100/$3}' || echo "      (无法获取)"
    
    echo "   ✅ ${CLUSTER} 清理完成"
    echo ""
}

# 遍历所有集群
TOTAL=${#CLUSTERS[@]}
COUNTER=0

for cluster in "${CLUSTERS[@]}"; do
    COUNTER=$((COUNTER + 1))
    echo "[$COUNTER/$TOTAL] 清理 $cluster"
    cleanup_cluster "$cluster"
    
    # 每处理3个集群休息一下
    if [ $((COUNTER % 3)) -eq 0 ] && [ $COUNTER -lt $TOTAL ]; then
        echo "⏸️  休息 3 秒..."
        sleep 3
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 批量清理完成！"
echo ""
echo "💡 下一步："
echo "   1. 等待 30-60 秒观察 tw_sock 是否下降"
echo "   2. 运行以下命令检查所有集群的 tw_sock 状态："
echo ""
echo "      for i in {11..20}; do"
echo "        echo \"=== kind\$i ===\";"
echo "        docker exec kind\$i-control-plane cat /proc/slabinfo | grep tw_sock_TCP | awk '{printf \"%s: %d\\n\", \$1, \$2}';"
echo "      done"
echo ""
echo "   3. 如果 tw_sock 下降到正常水平（<1000），可以开始运行任务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

