#!/bin/bash

# =============================================================================
# 测试脚本：创建单个 Kind11 集群（完整流程）
# =============================================================================

CLUSTER_NAME="kind11"
BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
LOG_DIR="$BASE_DIR/logs/docker/kind_creation"
LOG_FILE="$LOG_DIR/test_kind11.log"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 清空日志
> "$LOG_FILE"

# 定义镜像列表
APP_IMAGES=(
    "deathstarbench/social-network-microservices:latest"
    "jaegertracing/all-in-one:1.57"
    "memcached:1.6.7"
    "redis:6.2.4"
    "mongo:4.4.6"
    "yg397/openresty-thrift:xenial"
    "yg397/media-frontend:xenial"
    "alpine/git:latest"
)

OPENEBS_IMAGES=(
    "openebs/provisioner-localpv:3.4.0"
    "openebs/linux-utils:3.5.0"
    "openebs/node-disk-exporter:2.1.0"
    "openebs/node-disk-operator:2.1.0"
    "openebs/node-disk-manager:2.1.0"
)

PROMETHEUS_IMAGES=(
    "quay.io/prometheus/blackbox-exporter:v0.24.0"
    "quay.io/prometheus/node-exporter:v1.6.1"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0"
    "quay.io/prometheus/prometheus:v2.47.2"
    "quay.io/prometheus/pushgateway:v1.6.2"
    "registry.cn-wulanchabu.aliyuncs.com/moge1/kube-state-metrics:v2.3.0"
)

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
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

# 主流程
main() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "测试创建 Kind11 集群（完整流程）"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 检查是否已存在
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_error "集群 $CLUSTER_NAME 已存在，请先删除"
        return 1
    fi
    
    # 1. 创建集群
    log "步骤 1/6: 创建 Kind 集群..."
    if kind create cluster --name "$CLUSTER_NAME" --image jacksonarthurclark/aiopslab-kind-x86:latest >> "$LOG_FILE" 2>&1; then
        log_success "集群创建成功"
    else
        log_error "集群创建失败"
        return 1
    fi
    
    # 等待集群就绪
    log "等待集群 API Server 就绪..."
    sleep 10
    
    # 2. 加载应用镜像
    log "步骤 2/6: 加载应用镜像..."
    local loaded=0
    local failed=0
    for image in "${APP_IMAGES[@]}"; do
        if kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$LOG_FILE" 2>&1; then
            ((loaded++))
        else
            ((failed++))
            log_warning "镜像加载失败: $image"
        fi
    done
    log "应用镜像加载完成: $loaded 成功, $failed 失败"
    
    # 3. 加载 OpenEBS 镜像
    log "步骤 3/6: 加载 OpenEBS 镜像..."
    for image in "${OPENEBS_IMAGES[@]}"; do
        kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$LOG_FILE" 2>&1 || true
    done
    log_success "OpenEBS 镜像加载完成"
    
    # 4. 加载 Prometheus 镜像
    log "步骤 4/6: 加载 Prometheus 镜像..."
    for image in "${PROMETHEUS_IMAGES[@]}"; do
        kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$LOG_FILE" 2>&1 || true
    done
    log_success "Prometheus 镜像加载完成"
    
    # 5. 安装 OpenEBS
    log "步骤 5/6: 安装 OpenEBS..."
    if kubectl --context "kind-$CLUSTER_NAME" apply -f https://openebs.github.io/charts/openebs-operator.yaml >> "$LOG_FILE" 2>&1; then
        docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /run/udev >> "$LOG_FILE" 2>&1 || true
        
        # 等待 OpenEBS 就绪（最多等待60秒）
        if kubectl --context "kind-$CLUSTER_NAME" wait --for=condition=ready pod \
            -l name=openebs-localpv-provisioner \
            -n openebs \
            --timeout=60s >> "$LOG_FILE" 2>&1; then
            log_success "OpenEBS 安装成功"
        else
            log_warning "OpenEBS 未在60秒内就绪，继续下一步..."
        fi
    else
        log_warning "OpenEBS 安装失败（非致命错误）"
    fi
    
    # 6. 复制 socialNetwork 源代码
    log "步骤 6/6: 复制 socialNetwork 源代码..."
    
    # 关键修复：先创建目标目录
    log "创建目标目录 /var/lib/kubelet/hostpath..."
    if docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /var/lib/kubelet/hostpath >> "$LOG_FILE" 2>&1; then
        log_success "目标目录创建成功"
    else
        log_error "目标目录创建失败"
        return 1
    fi
    
    if [ -d "/tmp/socialNetwork_backup" ]; then
        # 使用备份
        if docker cp /tmp/socialNetwork_backup "${CLUSTER_NAME}-control-plane":/var/lib/kubelet/hostpath/socialNetwork >> "$LOG_FILE" 2>&1; then
            log_success "源代码复制成功（使用备份）"
        else
            log_error "源代码复制失败"
            return 1
        fi
    else
        # 从 kind 集群复制
        if docker cp kind-control-plane:/var/lib/kubelet/hostpath/socialNetwork /tmp/socialNetwork >> "$LOG_FILE" 2>&1; then
            # 创建备份供后续使用
            cp -r /tmp/socialNetwork /tmp/socialNetwork_backup
            if docker cp /tmp/socialNetwork "${CLUSTER_NAME}-control-plane":/var/lib/kubelet/hostpath/ >> "$LOG_FILE" 2>&1; then
                rm -rf /tmp/socialNetwork
                log_success "源代码复制成功"
            else
                log_error "源代码复制失败"
                return 1
            fi
        else
            log_error "无法从 kind 集群复制源代码"
            return 1
        fi
    fi
    
    # 7. 验证集群
    log "验证集群状态..."
    local node_status=$(kubectl --context "kind-$CLUSTER_NAME" get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$node_status" = "True" ]; then
        log_success "集群 $CLUSTER_NAME 创建完成并就绪！"
        
        # 显示集群信息
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "集群信息："
        kubectl --context "kind-$CLUSTER_NAME" get nodes
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 0
    else
        log_error "集群 $CLUSTER_NAME 创建完成，但状态未就绪"
        return 1
    fi
}

# 执行
START_TIME=$(date +%s)
if main; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "✅ 测试成功！总耗时: ${DURATION}秒"
    exit 0
else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "❌ 测试失败！总耗时: ${DURATION}秒"
    exit 1
fi

