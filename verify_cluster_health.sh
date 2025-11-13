#!/bin/bash

#############################################
# Kind 集群健康检查脚本
# 用途: 验证集群的完整性和健康状态
# 用法: ./verify_cluster_health.sh <cluster-name>
# 示例: ./verify_cluster_health.sh kind4
#############################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查参数
if [ $# -ne 1 ]; then
    echo -e "${RED}❌ 用法: $0 <cluster-name>${NC}"
    echo -e "${YELLOW}示例: $0 kind4${NC}"
    exit 1
fi

CLUSTER_NAME=$1
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔍 集群健康检查: ${CLUSTER_NAME}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查集群是否存在
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${RED}❌ 集群 ${CLUSTER_NAME} 不存在！${NC}"
    echo ""
    echo "现有集群："
    kind get clusters
    exit 1
fi

# 分数统计
TOTAL_CHECKS=0
PASSED_CHECKS=0

# 检查函数
check_item() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

# 1. 节点检查
echo -e "${YELLOW}━━━ 1. 节点状态 ━━━${NC}"
kubectl --context kind-${CLUSTER_NAME} get nodes
NODE_READY=$(kubectl --context kind-${CLUSTER_NAME} get nodes | grep -c "Ready")
check_item $( [ "$NODE_READY" -ge 1 ] && echo 0 || echo 1 ) "节点就绪 ($NODE_READY 个)"
echo ""

# 2. 系统 Pods 检查
echo -e "${YELLOW}━━━ 2. 系统组件 ━━━${NC}"
KUBE_SYSTEM_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -n kube-system --no-headers 2>/dev/null | wc -l)
KUBE_SYSTEM_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "  kube-system: $KUBE_SYSTEM_RUNNING/$KUBE_SYSTEM_PODS Running"
check_item $( [ "$KUBE_SYSTEM_RUNNING" -eq "$KUBE_SYSTEM_PODS" ] && echo 0 || echo 1 ) "kube-system 所有 Pods 运行中"

LOCAL_PATH_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -n local-path-storage --no-headers 2>/dev/null | wc -l)
LOCAL_PATH_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n local-path-storage --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "  local-path-storage: $LOCAL_PATH_RUNNING/$LOCAL_PATH_PODS Running"
check_item $( [ "$LOCAL_PATH_RUNNING" -eq "$LOCAL_PATH_PODS" ] && echo 0 || echo 1 ) "local-path-storage 所有 Pods 运行中"
echo ""

# 3. OpenEBS 检查
echo -e "${YELLOW}━━━ 3. OpenEBS 存储 ━━━${NC}"
if kubectl --context kind-${CLUSTER_NAME} get namespace openebs &>/dev/null; then
    kubectl --context kind-${CLUSTER_NAME} get pods -n openebs
    OPENEBS_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -n openebs --no-headers 2>/dev/null | wc -l)
    OPENEBS_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n openebs --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo ""
    echo "  OpenEBS Pods: $OPENEBS_RUNNING/$OPENEBS_PODS Running"
    check_item $( [ "$OPENEBS_RUNNING" -ge 1 ] && echo 0 || echo 1 ) "OpenEBS 核心组件运行中"
    
    # 检查 localpv-provisioner（最关键）
    LOCALPV_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n openebs --no-headers 2>/dev/null | grep localpv-provisioner | grep -c "Running" || echo "0")
    check_item $( [ "$LOCALPV_RUNNING" -ge 1 ] && echo 0 || echo 1 ) "openebs-localpv-provisioner 运行中"
else
    echo "  OpenEBS 未安装"
    check_item 1 "OpenEBS 已安装"
fi
echo ""

# 4. Prometheus 检查
echo -e "${YELLOW}━━━ 4. Prometheus 监控 ━━━${NC}"
if kubectl --context kind-${CLUSTER_NAME} get namespace observe &>/dev/null; then
    kubectl --context kind-${CLUSTER_NAME} get pods -n observe
    PROM_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -n observe --no-headers 2>/dev/null | wc -l)
    PROM_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n observe --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo ""
    echo "  Prometheus Pods: $PROM_RUNNING/$PROM_PODS Running"
    check_item $( [ "$PROM_RUNNING" -ge 1 ] && echo 0 || echo 1 ) "Prometheus 组件运行中"
    
    # 检查 prometheus-server（最关键）
    PROM_SERVER_RUNNING=$(kubectl --context kind-${CLUSTER_NAME} get pods -n observe --no-headers 2>/dev/null | grep prometheus-server | grep -c "Running" || echo "0")
    check_item $( [ "$PROM_SERVER_RUNNING" -ge 1 ] && echo 0 || echo 1 ) "prometheus-server 运行中"
else
    echo "  Prometheus 未安装"
    check_item 1 "Prometheus 已安装"
fi
echo ""

# 5. StorageClass 检查
echo -e "${YELLOW}━━━ 5. StorageClass ━━━${NC}"
kubectl --context kind-${CLUSTER_NAME} get sc
SC_COUNT=$(kubectl --context kind-${CLUSTER_NAME} get sc --no-headers 2>/dev/null | wc -l)
echo ""
check_item $( [ "$SC_COUNT" -ge 1 ] && echo 0 || echo 1 ) "StorageClass 可用 ($SC_COUNT 个)"
echo ""

# 6. 镜像检查
echo -e "${YELLOW}━━━ 6. 关键镜像 ━━━${NC}"
ALPINE_GIT=$(docker exec ${CONTROL_PLANE} crictl images 2>/dev/null | grep -c "alpine/git" || echo "0")
check_item $( [ "$ALPINE_GIT" -ge 1 ] && echo 0 || echo 1 ) "alpine/git 镜像已加载"

SOCIAL_NETWORK=$(docker exec ${CONTROL_PLANE} crictl images 2>/dev/null | grep -c "social-network-microservices" || echo "0")
check_item $( [ "$SOCIAL_NETWORK" -ge 1 ] && echo 0 || echo 1 ) "social-network-microservices 镜像已加载"

OPENEBS_IMG=$(docker exec ${CONTROL_PLANE} crictl images 2>/dev/null | grep -c "openebs/provisioner-localpv" || echo "0")
check_item $( [ "$OPENEBS_IMG" -ge 1 ] && echo 0 || echo 1 ) "OpenEBS 镜像已加载"
echo ""

# 7. 源代码文件检查
echo -e "${YELLOW}━━━ 7. socialNetwork 源代码 ━━━${NC}"
if docker exec ${CONTROL_PLANE} test -d /var/lib/kubelet/hostpath/socialNetwork 2>/dev/null; then
    echo "  /var/lib/kubelet/hostpath/socialNetwork/"
    docker exec ${CONTROL_PLANE} ls -la /var/lib/kubelet/hostpath/socialNetwork/ 2>/dev/null | head -10
    echo ""
    check_item 0 "socialNetwork 目录存在"
    
    # 检查关键子目录
    MEDIA_FRONTEND=$(docker exec ${CONTROL_PLANE} test -d /var/lib/kubelet/hostpath/socialNetwork/media-frontend && echo "1" || echo "0")
    check_item $( [ "$MEDIA_FRONTEND" -eq 1 ] && echo 0 || echo 1 ) "media-frontend 目录存在"
    
    GEN_LUA=$(docker exec ${CONTROL_PLANE} test -d /var/lib/kubelet/hostpath/socialNetwork/gen-lua && echo "1" || echo "0")
    check_item $( [ "$GEN_LUA" -eq 1 ] && echo 0 || echo 1 ) "gen-lua 目录存在"
else
    check_item 1 "socialNetwork 目录存在"
    echo -e "${YELLOW}  ⚠️  部分应用可能无法运行（如 media-frontend, nginx-thrift）${NC}"
fi
echo ""

# 8. 全局统计
echo -e "${YELLOW}━━━ 8. 全局统计 ━━━${NC}"
TOTAL_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -A --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo "0")
PENDING_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -A --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
ERROR_PODS=$(kubectl --context kind-${CLUSTER_NAME} get pods -A --no-headers 2>/dev/null | grep -cE "Error|CrashLoop|ImagePull" || echo "0")

echo "  总 Pods: $TOTAL_PODS"
echo "  运行中: $RUNNING_PODS"
echo "  等待中: $PENDING_PODS"
echo "  错误: $ERROR_PODS"
echo ""

# 如果有问题 Pods，显示详情
if [ "$ERROR_PODS" -gt 0 ] || [ "$PENDING_PODS" -gt 0 ]; then
    echo -e "${YELLOW}📋 问题 Pods 详情:${NC}"
    kubectl --context kind-${CLUSTER_NAME} get pods -A | grep -vE "Running|Completed|NAME" || echo "  无"
    echo ""
fi

# 最终评分
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 健康检查评分: $PASSED_CHECKS/$TOTAL_CHECKS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
    echo -e "${GREEN}🎉 集群状态完美！所有检查通过！${NC}"
    EXIT_CODE=0
elif [ "$PASSED_CHECKS" -ge $((TOTAL_CHECKS * 80 / 100)) ]; then
    echo -e "${YELLOW}✅ 集群基本健康，但有少量问题需要关注${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}⚠️  集群存在较多问题，建议检查上述失败项${NC}"
    EXIT_CODE=1
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "📋 推荐操作："
echo ""
echo "  查看所有 Pods:"
echo -e "    ${YELLOW}kubectl --context kind-${CLUSTER_NAME} get pods -A${NC}"
echo ""
echo "  查看问题 Pod 详情:"
echo -e "    ${YELLOW}kubectl --context kind-${CLUSTER_NAME} describe pod <pod-name> -n <namespace>${NC}"
echo ""
echo "  查看 Pod 日志:"
echo -e "    ${YELLOW}kubectl --context kind-${CLUSTER_NAME} logs <pod-name> -n <namespace>${NC}"
echo ""

exit $EXIT_CODE

