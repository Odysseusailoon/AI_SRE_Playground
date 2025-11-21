#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 清理 kind1-kind15 的应用资源（保留集群和基础设施）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志文件
LOG_DIR="cwy/log"
mkdir -p "$LOG_DIR"
CLEANUP_LOG="$LOG_DIR/cleanup_kind1_15_resources_$(date +%Y%m%d_%H%M%S).log"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🧹 清理 kind1-kind15 的应用资源${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}⚠️  注意: 此脚本会删除应用资源，但保留集群和基础设施${NC}"
echo -e "${YELLOW}📝 日志文件: $CLEANUP_LOG${NC}"
echo ""

{
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 清理 kind1-kind15 资源"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
} > "$CLEANUP_LOG"

# 要清理的应用 namespaces
APP_NAMESPACES=(
    "social-network"
    "hotel-reservation"
    "astronomy-shop"
    "default"  # 某些应用可能在 default namespace
)

# 清理单个集群的函数
cleanup_cluster() {
    local cluster=$1
    local context="kind-${cluster}"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔧 正在清理: ${cluster}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    {
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "清理集群: $cluster"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } >> "$CLEANUP_LOG"
    
    # 检查集群是否存在
    if ! kubectl cluster-info --context="$context" &>/dev/null; then
        echo -e "${RED}  ✗ 集群 ${cluster} 不存在或无法访问${NC}"
        echo "  ✗ 集群 ${cluster} 不存在或无法访问" >> "$CLEANUP_LOG"
        return 1
    fi
    
    # 1. 删除 Chaos Mesh 实验
    echo -e "${YELLOW}  → 删除 Chaos Mesh 故障注入实验...${NC}"
    echo "  → 删除 Chaos Mesh 故障注入实验" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        # 删除各种 chaos 资源
        kubectl delete podchaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        kubectl delete networkchaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        kubectl delete stresschaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        kubectl delete iochaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        kubectl delete timechaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        kubectl delete kernelchaos --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
    done
    
    # 2. 删除应用 deployments 和 statefulsets
    echo -e "${YELLOW}  → 删除应用的 Deployments 和 StatefulSets...${NC}"
    echo "  → 删除应用的 Deployments 和 StatefulSets" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        # 删除 deployments
        kubectl delete deployments --all -n "$ns" --context="$context" --timeout=60s 2>&1 | tee -a "$CLEANUP_LOG" || true
        # 删除 statefulsets
        kubectl delete statefulsets --all -n "$ns" --context="$context" --timeout=60s 2>&1 | tee -a "$CLEANUP_LOG" || true
        # 删除 daemonsets (可能有一些应用的 daemonsets)
        kubectl delete daemonsets --all -n "$ns" --context="$context" --timeout=60s 2>&1 | tee -a "$CLEANUP_LOG" || true
    done
    
    # 3. 删除所有 pods（强制删除残留的）
    echo -e "${YELLOW}  → 强制删除残留的 Pods...${NC}"
    echo "  → 强制删除残留的 Pods" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        kubectl delete pods --all -n "$ns" --context="$context" --grace-period=0 --force --timeout=60s 2>&1 | tee -a "$CLEANUP_LOG" || true
    done
    
    # 4. 删除 services (保留 kubernetes 默认服务)
    echo -e "${YELLOW}  → 删除应用的 Services...${NC}"
    echo "  → 删除应用的 Services" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        if [ "$ns" = "default" ]; then
            # default namespace 只删除非系统服务
            kubectl get svc -n default --context="$context" -o name 2>/dev/null | grep -v "service/kubernetes" | xargs -r kubectl delete -n default --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        else
            kubectl delete svc --all -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        fi
    done
    
    # 5. 删除 ConfigMaps 和 Secrets (保留系统的)
    echo -e "${YELLOW}  → 删除应用的 ConfigMaps 和 Secrets...${NC}"
    echo "  → 删除应用的 ConfigMaps 和 Secrets" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        # 删除非系统的 configmaps
        kubectl get cm -n "$ns" --context="$context" -o name 2>/dev/null | grep -v "kube-root-ca.crt" | xargs -r kubectl delete -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
        # 删除非系统的 secrets
        kubectl get secret -n "$ns" --context="$context" -o name 2>/dev/null | grep -v "default-token" | grep -v "service-account-token" | xargs -r kubectl delete -n "$ns" --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
    done
    
    # 6. 删除 PVCs
    echo -e "${YELLOW}  → 删除 PersistentVolumeClaims...${NC}"
    echo "  → 删除 PersistentVolumeClaims" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        kubectl delete pvc --all -n "$ns" --context="$context" --timeout=60s 2>&1 | tee -a "$CLEANUP_LOG" || true
    done
    
    # 7. 删除应用相关的 namespaces (除了 default)
    echo -e "${YELLOW}  → 删除应用 Namespaces...${NC}"
    echo "  → 删除应用 Namespaces" >> "$CLEANUP_LOG"
    
    for ns in "${APP_NAMESPACES[@]}"; do
        if [ "$ns" != "default" ]; then
            if kubectl get namespace "$ns" --context="$context" &>/dev/null; then
                kubectl delete namespace "$ns" --context="$context" --timeout=120s 2>&1 | tee -a "$CLEANUP_LOG" || true
            fi
        fi
    done
    
    # 8. 清理孤立的 PVs (状态为 Released 或 Failed)
    echo -e "${YELLOW}  → 清理孤立的 PersistentVolumes...${NC}"
    echo "  → 清理孤立的 PersistentVolumes" >> "$CLEANUP_LOG"
    
    kubectl get pv --context="$context" -o json 2>/dev/null | \
        jq -r '.items[] | select(.status.phase == "Released" or .status.phase == "Failed") | .metadata.name' | \
        xargs -r -I {} kubectl delete pv {} --context="$context" --timeout=30s 2>&1 | tee -a "$CLEANUP_LOG" || true
    
    echo -e "${GREEN}  ✓ 集群 ${cluster} 清理完成${NC}"
    echo "  ✓ 集群 ${cluster} 清理完成" >> "$CLEANUP_LOG"
}

# 清理所有集群
echo -e "${YELLOW}开始清理 kind1-kind15 ...${NC}"
echo ""

for i in {1..15}; do
    cleanup_cluster "kind${i}"
    echo ""
done

# 总结
{
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 清理完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
} >> "$CLEANUP_LOG"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 所有集群清理完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📋 保留的资源:${NC}"
echo -e "  ✓ Kind 集群本身"
echo -e "  ✓ 基础设施 namespaces (openebs, prometheus, chaos-mesh, kube-system)"
echo -e "  ✓ 系统组件 (prometheus, openebs, chaos-mesh 等)"
echo ""
echo -e "${YELLOW}🗑️  已删除的资源:${NC}"
echo -e "  ✓ 应用 namespaces (social-network, hotel-reservation, astronomy-shop)"
echo -e "  ✓ 应用的 Deployments, StatefulSets, DaemonSets"
echo -e "  ✓ 应用的 Pods, Services, ConfigMaps, Secrets"
echo -e "  ✓ Chaos Mesh 故障注入实验"
echo -e "  ✓ PVCs 和孤立的 PVs"
echo ""
echo -e "${BLUE}📝 详细日志: $CLEANUP_LOG${NC}"
echo ""

# 验证清理结果
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}📊 清理后状态检查 (kind1 示例):${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if kubectl cluster-info --context="kind-kind1" &>/dev/null; then
    echo -e "${GREEN}应用 Pods 数量:${NC}"
    for ns in "${APP_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" --context="kind-kind1" &>/dev/null; then
            POD_COUNT=$(kubectl get pods -n "$ns" --context="kind-kind1" --no-headers 2>/dev/null | wc -l)
            echo -e "  - Namespace ${ns}: ${POD_COUNT} pods"
        else
            echo -e "  - Namespace ${ns}: ${GREEN}✓ 已删除${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}Chaos 实验数量:${NC}"
    CHAOS_COUNT=$(kubectl get podchaos,networkchaos,stresschaos --all-namespaces --context="kind-kind1" --no-headers 2>/dev/null | wc -l)
    echo -e "  - 故障注入实验: ${CHAOS_COUNT}"
    
    echo ""
    echo -e "${GREEN}PV 状态:${NC}"
    kubectl get pv --context="kind-kind1" --no-headers 2>/dev/null | awk '{print "  - " $1 ": " $5}'
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 资源清理脚本执行完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

