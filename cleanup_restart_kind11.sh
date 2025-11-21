#!/bin/bash
# 先删除有问题的组件，再重启 kind11 以彻底清理 tw_sock

set -e

CLUSTER="kind11"
LOG_FILE="logs/cleanup_restart_kind11.log"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Kind11 彻底清理方案：先删组件 → 再重启容器"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. 记录当前状态
echo "📊 步骤1: 记录当前 tw_sock 状态"
echo "当前 tw_sock:"
docker exec ${CLUSTER}-control-plane cat /proc/slabinfo | grep tw_sock_TCP | \
  awk '{printf "  %s: %d / %d (%.1f%%)\n", $1, $2, $3, $2*100/$3}'
echo ""

# 2. 删除有问题的组件
echo "🗑️  步骤2: 删除有问题的组件"
echo ""

echo "  删除 OpenEBS..."
docker exec ${CLUSTER}-control-plane kubectl delete namespace openebs --grace-period=0 --force 2>&1 | head -5
echo ""

echo "  删除 Chaos Mesh（如果存在）..."
docker exec ${CLUSTER}-control-plane kubectl delete namespace chaos-mesh --grace-period=0 --force 2>/dev/null || echo "    (已不存在)"
echo ""

echo "  删除 Prometheus（如果存在）..."
docker exec ${CLUSTER}-control-plane kubectl delete namespace observe --grace-period=0 --force 2>/dev/null || echo "    (已不存在)"
echo ""

echo "  等待删除完成（10秒）..."
sleep 10
echo ""

# 3. 检查删除后的 tw_sock
echo "📊 步骤3: 检查删除后的 tw_sock"
docker exec ${CLUSTER}-control-plane cat /proc/slabinfo | grep tw_sock_TCP | \
  awk '{printf "  %s: %d\n", $1, $2}'
echo ""

# 4. 重启容器
echo "🔄 步骤4: 重启 ${CLUSTER} 容器"
echo "  执行: docker restart ${CLUSTER}-control-plane"
docker restart ${CLUSTER}-control-plane
echo "  ✅ 重启命令已发送"
echo ""

# 5. 等待容器启动
echo "⏳ 步骤5: 等待容器启动（30秒）..."
sleep 30
echo ""

# 6. 检查容器状态
echo "📋 步骤6: 检查容器状态"
if docker ps --format "{{.Names}}" | grep -q "^${CLUSTER}-control-plane$"; then
    echo "  ✅ 容器正在运行"
else
    echo "  ❌ 容器未启动"
    exit 1
fi
echo ""

# 7. 检查 tw_sock 是否清零
echo "📊 步骤7: 检查 tw_sock 状态（应该接近 0）"
docker exec ${CLUSTER}-control-plane cat /proc/slabinfo 2>/dev/null | grep tw_sock_TCP | \
  awk '{printf "  %s: %d / %d (%.1f%%)\n", $1, $2, $3, $2*100/$3}' || echo "  (容器还在启动中)"
echo ""

# 8. 检查基础组件
echo "📋 步骤8: 检查 K8s 核心组件"
sleep 10
docker exec ${CLUSTER}-control-plane kubectl get pods -n kube-system 2>&1 | head -10 || echo "  (API Server 还在启动)"
echo ""

# 9. 检查被删除的命名空间是否真的没了
echo "📋 步骤9: 确认已删除的组件"
echo "  检查 namespace:"
docker exec ${CLUSTER}-control-plane kubectl get namespace 2>&1 | grep -E "openebs|chaos-mesh|observe" || echo "    ✅ 已删除的组件确认清理"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Kind11 清理完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 最终状态总结:"
echo ""
echo "1. tw_sock 状态:"
docker exec ${CLUSTER}-control-plane cat /proc/slabinfo 2>/dev/null | grep tw_sock_TCP | \
  awk '{printf "   %s: %d\n", $1, $2}'
echo ""

echo "2. 运行中的 namespace:"
docker exec ${CLUSTER}-control-plane kubectl get namespace --no-headers 2>/dev/null | awk '{print "   - " $1}'
echo ""

echo "3. 非 Running 的 Pod:"
NON_RUNNING=$(docker exec ${CLUSTER}-control-plane kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | wc -l)
if [ "$NON_RUNNING" -le 1 ]; then
    echo "   ✅ 没有异常 Pod"
else
    echo "   ⚠️  有 $((NON_RUNNING - 1)) 个非正常 Pod"
    docker exec ${CLUSTER}-control-plane kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | head -10
fi
echo ""

echo "💡 下一步："
echo "   现在可以运行测试："
echo "   cd /home/ecs-user/projects/AI_SRE_Playground-echo"
echo "   nohup bash run_kind11_test.sh > logs/test/kind11_wrapper.log 2>&1 &"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"

