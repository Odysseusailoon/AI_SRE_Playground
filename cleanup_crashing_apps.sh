#!/bin/bash
# 清理 kind1 中不断崩溃的应用，以降低 tw_sock 压力
# 这些应用在任务启动时会自动重新部署

set -e

CLUSTER="kind1"
CONTEXT="kind-${CLUSTER}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 清理 ${CLUSTER} 中崩溃的应用（保留基础设施）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. 删除 Chaos Mesh（重启最严重：200+次）
echo ""
echo "1️⃣  删除 Chaos Mesh..."
docker exec ${CLUSTER}-control-plane kubectl delete namespace chaos-mesh --grace-period=0 --force 2>/dev/null || true
echo "   ✅ Chaos Mesh 已删除"

# 2. 删除 Prometheus（会在任务启动时重新部署）
echo ""
echo "2️⃣  删除 Prometheus..."
docker exec ${CLUSTER}-control-plane kubectl delete namespace observe --grace-period=0 --force 2>/dev/null || true
echo "   ✅ Prometheus 已删除"

# 3. 删除微服务应用（会在任务启动时重新部署）
echo ""
echo "3️⃣  删除微服务应用..."

# Hotel Reservation
docker exec ${CLUSTER}-control-plane kubectl delete namespace test-hotel-reservation --grace-period=0 --force 2>/dev/null || true
echo "   ✅ Hotel Reservation 已删除"

# Social Network
docker exec ${CLUSTER}-control-plane kubectl delete namespace social-network --grace-period=0 --force 2>/dev/null || true
echo "   ✅ Social Network 已删除"

# Astronomy Shop
docker exec ${CLUSTER}-control-plane kubectl delete namespace otel-demo --grace-period=0 --force 2>/dev/null || true
echo "   ✅ Astronomy Shop 已删除"

# 4. 保留 OpenEBS 和 kube-system（基础设施）
echo ""
echo "4️⃣  保留基础设施："
echo "   ✅ OpenEBS (local-path-storage)"
echo "   ✅ kube-system (K8s 核心组件)"

# 5. 等待清理完成
echo ""
echo "5️⃣  等待清理完成..."
sleep 10

# 6. 检查 tw_sock 状态
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 tw_sock 状态："
docker exec ${CLUSTER}-control-plane cat /proc/slabinfo | grep tw_sock_TCP | \
  awk '{printf "   %s: %d / %d (%.1f%%)\n", $1, $2, $3, $2*100/$3}'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 清理完成！"
echo ""
echo "💡 下一步："
echo "   1. 等待 30-60 秒观察 tw_sock 是否下降"
echo "   2. 如果 tw_sock 下降到正常水平（<1000），可以开始运行任务"
echo "   3. 任务启动时会自动重新部署需要的应用"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

