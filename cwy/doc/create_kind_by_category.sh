#!/bin/bash

# =============================================================================
# 按类别创建和加载镜像到Kind集群（支持单个或多个集群）
# 使用方法：
#   ./create_kind_by_category.sh <kind名称或列表> <类别>
# 
# 类别选项：
#   - social_network      (Social Network应用，25个镜像)
#   - hotel_reservation   (Hotel Reservation应用，31个镜像)
#   - astronomy_shop      (Astronomy Shop应用，22个镜像)
#
# 示例：
#   单个集群：./create_kind_by_category.sh kind11 social_network
#   多个集群：./create_kind_by_category.sh "kind1,kind11" social_network
#   范围集群：./create_kind_by_category.sh "1-3" social_network  (创建 kind1, kind2, kind3)
#
# 后台运行：
#   nohup bash create_kind_by_category.sh "kind1,kind11" social_network > ../log/multi_creation.log 2>&1 &
# =============================================================================

set -e

# 参数检查
if [ $# -ne 2 ]; then
    echo "❌ 错误：需要2个参数"
    echo "用法: $0 <kind名称或列表> <类别>"
    echo ""
    echo "类别选项："
    echo "  - social_network      (Social Network应用)"
    echo "  - hotel_reservation   (Hotel Reservation应用)"
    echo "  - astronomy_shop      (Astronomy Shop应用)"
    echo ""
    echo "示例："
    echo "  单个: $0 kind11 social_network"
    echo "  多个: $0 'kind1,kind11' social_network"
    echo "  范围: $0 '1-5' social_network"
    exit 1
fi

CLUSTER_INPUT="$1"
CATEGORY="$2"

# 解析集群名称列表
CLUSTER_LIST=()

# 判断输入格式
if [[ "$CLUSTER_INPUT" == *","* ]]; then
    # 逗号分隔的列表: "kind1,kind11"
    IFS=',' read -ra CLUSTER_LIST <<< "$CLUSTER_INPUT"
elif [[ "$CLUSTER_INPUT" =~ ^[0-9]+-[0-9]+$ ]]; then
    # 数字范围: "1-5"
    START=$(echo "$CLUSTER_INPUT" | cut -d'-' -f1)
    END=$(echo "$CLUSTER_INPUT" | cut -d'-' -f2)
    for i in $(seq $START $END); do
        CLUSTER_LIST+=("kind$i")
    done
else
    # 单个集群名称
    CLUSTER_LIST=("$CLUSTER_INPUT")
fi

# 验证类别
if [[ "$CATEGORY" != "social_network" && "$CATEGORY" != "hotel_reservation" && "$CATEGORY" != "astronomy_shop" ]]; then
    echo "❌ 错误：无效的类别 '$CATEGORY'"
    echo "有效类别: social_network, hotel_reservation, astronomy_shop"
    exit 1
fi

# 配置
BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
LOG_DIR="$BASE_DIR/cwy/log"
mkdir -p "$LOG_DIR"

# 显示待创建的集群列表
echo "=== 待创建的集群 ==="
echo "集群列表: ${CLUSTER_LIST[*]}"
echo "应用类别: $CATEGORY"
echo "集群数量: ${#CLUSTER_LIST[@]}"
echo ""

# 循环处理每个集群
for CLUSTER_NAME in "${CLUSTER_LIST[@]}"; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 开始处理集群: $CLUSTER_NAME"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    log "${RED}❌ $1${NC}"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# =============================================================================
# 镜像定义
# =============================================================================

# 基础设施镜像（所有类别都需要）
BASE_IMAGES=(
    # OpenEBS (5个)
    "openebs/provisioner-localpv:3.4.0"
    "openebs/linux-utils:3.5.0"
    "openebs/node-disk-exporter:2.1.0"
    "openebs/node-disk-operator:2.1.0"
    "openebs/node-disk-manager:2.1.0"
    
    # Prometheus (7个)
    "quay.io/prometheus/blackbox-exporter:v0.24.0"
    "quay.io/prometheus/node-exporter:v1.6.1"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0"
    "quay.io/prometheus/prometheus:v2.47.2"
    "quay.io/prometheus/pushgateway:v1.6.2"
    "registry.cn-wulanchabu.aliyuncs.com/moge1/kube-state-metrics:v2.3.0"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1"
    
    # Chaos Mesh (4个)
    "ghcr.io/chaos-mesh/chaos-mesh:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-daemon:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-dashboard:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-coredns:v0.2.6"
)

# Social Network 应用镜像
SOCIAL_NETWORK_IMAGES=(
    "deathstarbench/social-network-microservices:latest"
    "jaegertracing/all-in-one:1.57"
    "memcached:1.6.7"
    "redis:6.2.4"
    "mongo:4.4.6"
    "yg397/openresty-thrift:xenial"
    "yg397/media-frontend:xenial"
    "alpine/git:latest"
    "deathstarbench/wrk2-client:latest"
)

# Hotel Reservation 应用镜像
HOTEL_RESERVATION_IMAGES=(
    "deathstarbench/hotel-reservation:latest"
    "hashicorp/consul:latest"
    "jaegertracing/all-in-one:1.57"
    "igorrudyk1/hotel_reserv_frontend_single_node:latest"
    "igorrudyk1/hotel_reserv_geo_single_node:latest"
    "igorrudyk1/hotel_reserv_profile_single_node:latest"
    "igorrudyk1/hotel_reserv_rate_single_node:latest"
    "igorrudyk1/hotel_reserv_recommendation_single_node:latest"
    "igorrudyk1/hotel_reserv_reserve_single_node:latest"
    "igorrudyk1/hotel_reserv_search_single_node:latest"
    "igorrudyk1/hotel_reserv_user_single_node:latest"
    "yinfangchen/hotelreservation:latest"
    "memcached:latest"
    "memcached:1.6.7"
    "mongo:4.4.6"
    "deathstarbench/wrk2-client:latest"
)

# Astronomy Shop 应用镜像
ASTRONOMY_SHOP_IMAGES=(
    "ghcr.io/open-telemetry/demo:1.11.2"
    "otel/opentelemetry-collector-contrib:0.118.0"
    "busybox:latest"
    "redis:7.0-alpine"
    "bitnami/kafka:latest"
    "postgres:16"
)

# =============================================================================
# 主流程
# =============================================================================

START_TIME=$(date +%s)

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "🚀 创建 Kind 集群并加载镜像"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "集群名称: $CLUSTER_NAME"
log_info "应用类别: $CATEGORY"
log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
log ""

# 选择应用镜像
case $CATEGORY in
    social_network)
        APP_IMAGES=("${SOCIAL_NETWORK_IMAGES[@]}")
        APP_NAME="Social Network"
        ;;
    hotel_reservation)
        APP_IMAGES=("${HOTEL_RESERVATION_IMAGES[@]}")
        APP_NAME="Hotel Reservation"
        ;;
    astronomy_shop)
        APP_IMAGES=("${ASTRONOMY_SHOP_IMAGES[@]}")
        APP_NAME="Astronomy Shop"
        ;;
esac

TOTAL_IMAGES=$((${#BASE_IMAGES[@]} + ${#APP_IMAGES[@]}))
log_info "镜像统计: 基础设施(${#BASE_IMAGES[@]}) + $APP_NAME(${#APP_IMAGES[@]}) = 总计 $TOTAL_IMAGES 个"
log ""

# 检查集群是否已存在
log "━━━ 步骤 1/6: 检查集群状态 ━━━"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_warning "集群 $CLUSTER_NAME 已存在"
    log_error "脚本终止：请先手动删除集群或使用不同的集群名称"
    log "提示: kind delete cluster --name $CLUSTER_NAME"
    exit 1
else
    log_info "集群不存在，将创建新集群"
fi
log ""

# 创建集群
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log "━━━ 步骤 2/6: 创建 Kind 集群 ━━━"
    log "执行: kind create cluster --name $CLUSTER_NAME --image jacksonarthurclark/aiopslab-kind-x86:latest"
    
    if kind create cluster --name "$CLUSTER_NAME" --image jacksonarthurclark/aiopslab-kind-x86:latest; then
        log_success "集群创建成功"
    else
        log_error "集群创建失败"
        exit 1
    fi
    
    log "等待 API Server 就绪..."
    sleep 10
    
    log "创建 /run/udev 目录（OpenEBS ndm 需要）..."
    if docker exec ${CLUSTER_NAME}-control-plane mkdir -p /run/udev > /dev/null 2>&1; then
        log_success "/run/udev 目录已创建"
    else
        log_warning "/run/udev 目录创建失败（非致命错误）"
    fi
    
    # Social Network 应用需要源代码
    if [[ "$CATEGORY" == "social_network" ]]; then
        log "准备 Social Network 源代码（DeathStarBench）..."
        
        # 创建目录
        docker exec ${CLUSTER_NAME}-control-plane mkdir -p /var/lib/kubelet/hostpath/socialNetwork
        
        # 查找可用的源集群（从任何运行中且有源代码的 kind 集群复制）
        SOURCE_CLUSTER=""
        
        # 遍历所有运行中的 kind 集群，找到第一个有源代码的
        for container in $(docker ps --filter "name=kind.*-control-plane" --format "{{.Names}}" | sed 's/-control-plane//'); do
            # 跳过当前正在创建的集群
            if [[ "$container" == "$CLUSTER_NAME" ]]; then
                continue
            fi
            
            # 检查是否有源代码（验证 CMakeLists.txt 文件存在）
            if docker exec ${container}-control-plane test -f /var/lib/kubelet/hostpath/socialNetwork/CMakeLists.txt 2>/dev/null; then
                SOURCE_CLUSTER="$container"
                log "找到源集群: $SOURCE_CLUSTER"
                break
            fi
        done
        
        # 执行复制
        if [[ -n "$SOURCE_CLUSTER" ]]; then
            log "从 ${SOURCE_CLUSTER} 复制 DeathStarBench 源代码..."
            if docker cp ${SOURCE_CLUSTER}-control-plane:/var/lib/kubelet/hostpath/socialNetwork /tmp/socialNetwork_temp_$$ && \
               docker cp /tmp/socialNetwork_temp_$$/. ${CLUSTER_NAME}-control-plane:/var/lib/kubelet/hostpath/socialNetwork/ && \
               rm -rf /tmp/socialNetwork_temp_$$; then
                log_success "源代码已从 ${SOURCE_CLUSTER} 复制"
            else
                log_error "源代码复制失败"
                log "请手动复制源代码到集群内"
                exit 1
            fi
        else
            log_error "未找到包含 Social Network 源代码的集群"
            log "请确保至少有一个集群（如 kind2）包含 DeathStarBench 源代码"
            log "或从 GitHub 手动克隆：https://github.com/delimitrou/DeathStarBench"
            exit 1
        fi
    fi
    log ""
else
    log "━━━ 步骤 2/6: 跳过（集群已存在）━━━"
    log ""
fi

# 加载基础设施镜像
log "━━━ 步骤 3/6: 加载基础设施镜像 (${#BASE_IMAGES[@]}个) ━━━"
LOADED=0
FAILED=0

for image in "${BASE_IMAGES[@]}"; do
    echo -n "  加载: $image ... "
    if kind load docker-image "$image" --name "$CLUSTER_NAME" > /dev/null 2>&1; then
        echo "✅"
        ((LOADED++)) || true
    else
        echo "❌"
        ((FAILED++)) || true
    fi
done

log_success "基础设施镜像: $LOADED 成功, $FAILED 失败"
log ""

# 加载应用镜像
log "━━━ 步骤 4/6: 加载 $APP_NAME 镜像 (${#APP_IMAGES[@]}个) ━━━"
APP_LOADED=0
APP_FAILED=0

for image in "${APP_IMAGES[@]}"; do
    echo -n "  加载: $image ... "
    if kind load docker-image "$image" --name "$CLUSTER_NAME" > /dev/null 2>&1; then
        echo "✅"
        ((APP_LOADED++)) || true
    else
        echo "❌"
        ((APP_FAILED++)) || true
    fi
done

log_success "应用镜像: $APP_LOADED 成功, $APP_FAILED 失败"
log ""

# 设置 tcp_fin_timeout（优化网络性能）
log "━━━ 步骤 5/6: 优化网络配置 ━━━"
log "设置 tcp_fin_timeout=15 秒..."
if docker exec ${CLUSTER_NAME}-control-plane sysctl -w net.ipv4.tcp_fin_timeout=15 > /dev/null 2>&1; then
    log_success "网络参数已优化"
else
    log_warning "网络参数设置失败（非致命错误）"
fi
log ""

# 验证集群
log "━━━ 步骤 6/6: 验证集群状态 ━━━"
log "检查节点状态..."
kubectl --context "kind-${CLUSTER_NAME}" get nodes

log ""
log "检查镜像数量..."
IMAGE_COUNT=$(docker exec ${CLUSTER_NAME}-control-plane crictl images 2>/dev/null | wc -l)
log_info "集群内镜像总数: $((IMAGE_COUNT - 1)) 个"
log ""

# 完成
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "🎉 创建完成！"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log_info "集群名称: $CLUSTER_NAME"
log_info "应用类别: $CATEGORY ($APP_NAME)"
log_info "镜像加载: 基础设施($LOADED/$((${#BASE_IMAGES[@]}))) + 应用($APP_LOADED/${#APP_IMAGES[@]})"
log_info "总计耗时: ${MINUTES}分${SECONDS}秒"
log_info "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
log ""
log "💡 下一步："
log "   1. 查看节点: kubectl --context kind-$CLUSTER_NAME get nodes"
log "   2. 查看镜像: docker exec ${CLUSTER_NAME}-control-plane crictl images"
log "   3. 安装应用: 根据需要部署微服务"
log ""

done  # 集群循环结束

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 所有集群创建完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "已创建集群: ${CLUSTER_LIST[*]}"
echo "总计: ${#CLUSTER_LIST[@]} 个集群"
echo ""

exit 0

