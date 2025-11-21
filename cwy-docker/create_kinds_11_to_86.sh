#!/bin/bash

# =============================================================================
# 批量创建 Kind 集群脚本 (kind1 - kind86)
# =============================================================================

# 配置
# 批量创建 kind1 - kind86
START_NUM=1
END_NUM=86
BASE_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo"
LOG_DIR="$BASE_DIR/logs/docker/kind_creation"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志文件（固定名字，不加时间戳）
MAIN_LOG="$LOG_DIR/batch_creation.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

# 清空旧日志文件（每次运行时覆盖）
> "$MAIN_LOG"
> "$SUMMARY_LOG"

# 定义镜像列表
APP_IMAGES=(
    # Social Network 镜像
    "deathstarbench/social-network-microservices:latest"
    "jaegertracing/all-in-one:1.57"
    "memcached:1.6.7"
    "redis:6.2.4"
    "mongo:4.4.6"
    "yg397/openresty-thrift:xenial"
    "yg397/media-frontend:xenial"
    "alpine/git:latest"
    # Hotel Reservation 镜像
    "deathstarbench/hotel-reservation:latest"
    "consul:1.5"
    "hashicorp/consul:latest"
    "igorrudyk1/hotel_reserv_frontend_single_node:latest"
    "igorrudyk1/hotel_reserv_geo_single_node:latest"
    "igorrudyk1/hotel_reserv_profile_single_node:latest"
    "igorrudyk1/hotel_reserv_rate_single_node:latest"
    "igorrudyk1/hotel_reserv_recommendation_single_node:latest"
    "igorrudyk1/hotel_reserv_reserve_single_node:latest"
    "igorrudyk1/hotel_reserv_search_single_node:latest"
    "igorrudyk1/hotel_reserv_user_single_node:latest"
    "yinfangchen/hotelreservation:latest"
    # Workload 镜像
    "deathstarbench/wrk2-client:latest"
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
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1"
)

CHAOS_MESH_IMAGES=(
    "ghcr.io/chaos-mesh/chaos-mesh:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-daemon:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-dashboard:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-coredns:v0.2.6"
)

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$MAIN_LOG"
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

# Summary 日志函数
log_summary() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$SUMMARY_LOG"
}

# 创建单个集群的函数
create_single_cluster() {
    local CLUSTER_NAME=$1
    local start_time=$(date +%s)
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "开始处理集群: $CLUSTER_NAME"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local status="SUCCESS"
    local error_msg=""
    local cluster_exists=false
    
    # 检测集群是否已存在
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "集群 $CLUSTER_NAME 已存在，跳过创建步骤，检查Prometheus..."
        cluster_exists=true
        
        # 检查并修复容器状态
        log "检查集群容器健康状态..."
        local containers_ok=true
        
        # 获取该集群的所有容器
        local cluster_containers=$(docker ps -a --filter "name=${CLUSTER_NAME}-" --format "{{.Names}}")
        
        for container in $cluster_containers; do
            local container_status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
            
            if [ "$container_status" != "running" ]; then
                log_warning "容器 $container 状态异常: $container_status，尝试重启..."
                
                if docker start "$container" >> "$MAIN_LOG" 2>&1; then
                    log_success "容器 $container 重启成功"
                    # 等待容器稳定
                    sleep 5
    else
                    log_error "容器 $container 重启失败"
                    containers_ok=false
                fi
            fi
        done
        
        if [ "$containers_ok" = false ]; then
            log_error "集群容器状态异常且无法修复，跳过此集群"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_summary "$CLUSTER_NAME: ❌ FAILED (容器异常) - ${duration}秒"
        return 1
        fi
        
        log_success "所有容器健康检查通过"
    fi
    
    # 1. 加载镜像（对所有集群执行，无论是否已存在）
    log "步骤1: 加载应用镜像..."
    local loaded=0
    local failed=0
    for image in "${APP_IMAGES[@]}"; do
        if kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$MAIN_LOG" 2>&1; then
            ((loaded++))
        else
            ((failed++))
        fi
    done
    log "应用镜像: $loaded 成功, $failed 失败"
    
    log "步骤2: 加载 OpenEBS 镜像..."
    for image in "${OPENEBS_IMAGES[@]}"; do
        kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$MAIN_LOG" 2>&1 || true
    done
    log_success "OpenEBS 镜像加载完成"
    
    log "步骤3: 加载 Prometheus 镜像..."
    for image in "${PROMETHEUS_IMAGES[@]}"; do
        kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$MAIN_LOG" 2>&1 || true
    done
    log_success "Prometheus 镜像加载完成"
    
    log "步骤4: 加载 Chaos Mesh 镜像..."
    for image in "${CHAOS_MESH_IMAGES[@]}"; do
        kind load docker-image "$image" --name "$CLUSTER_NAME" >> "$MAIN_LOG" 2>&1 || true
    done
    log_success "Chaos Mesh 镜像加载完成"
    
    # 5. 创建集群（如果不存在）
    if [ "$cluster_exists" = false ]; then
    log "步骤 4: 创建 Kind 集群..."
    if kind create cluster --name "$CLUSTER_NAME" --image jacksonarthurclark/aiopslab-kind-x86:latest >> "$MAIN_LOG" 2>&1; then
        log_success "集群创建成功"
    else
        log_error "集群创建失败"
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_summary "$CLUSTER_NAME: ❌ FAILED (集群创建失败) - ${duration}秒"
        return 1
    fi
    
    # 等待 API Server 就绪
    log "等待 API Server 就绪..."
    sleep 10
    
    # 5. 安装 OpenEBS
    log "步骤 5/7: 安装 OpenEBS..."
    if kubectl --context "kind-$CLUSTER_NAME" apply -f https://openebs.github.io/charts/openebs-operator.yaml >> "$MAIN_LOG" 2>&1; then
        docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /run/udev >> "$MAIN_LOG" 2>&1 || true
        
        # 等待 OpenEBS 就绪（最多等待60秒）
        if kubectl --context "kind-$CLUSTER_NAME" wait --for=condition=ready pod \
            -l name=openebs-localpv-provisioner \
            -n openebs \
            --timeout=60s >> "$MAIN_LOG" 2>&1; then
            log_success "OpenEBS 安装成功"
        else
            log_warning "OpenEBS 未在60秒内就绪，继续下一步..."
            status="PARTIAL"
            error_msg="OpenEBS超时"
        fi
    else
        log_warning "OpenEBS 安装失败（非致命错误）"
        status="PARTIAL"
        error_msg="OpenEBS失败"
    fi
    
    # 6. 复制 socialNetwork 源代码
    log "步骤 6/7: 复制 socialNetwork 源代码..."
    
    # 关键修复：先创建目标目录
    if ! docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /var/lib/kubelet/hostpath >> "$MAIN_LOG" 2>&1; then
        log_error "目标目录创建失败"
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_summary "$CLUSTER_NAME: ❌ FAILED (目录创建失败) - ${duration}秒"
        return 1
    fi
    
    if [ -d "/tmp/socialNetwork_backup" ]; then
        # 使用备份
        if docker cp /tmp/socialNetwork_backup "${CLUSTER_NAME}-control-plane":/var/lib/kubelet/hostpath/socialNetwork >> "$MAIN_LOG" 2>&1; then
            log_success "源代码复制成功（使用备份）"
        else
            log_error "源代码复制失败"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_summary "$CLUSTER_NAME: ❌ FAILED (源代码复制失败) - ${duration}秒"
            return 1
        fi
    else
        # 从 kind 集群复制
        if docker cp kind-control-plane:/var/lib/kubelet/hostpath/socialNetwork /tmp/socialNetwork >> "$MAIN_LOG" 2>&1; then
            # 创建备份供后续使用
            cp -r /tmp/socialNetwork /tmp/socialNetwork_backup
            if docker cp /tmp/socialNetwork "${CLUSTER_NAME}-control-plane":/var/lib/kubelet/hostpath/ >> "$MAIN_LOG" 2>&1; then
                rm -rf /tmp/socialNetwork
                log_success "源代码复制成功"
            else
                log_error "源代码复制失败"
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                log_summary "$CLUSTER_NAME: ❌ FAILED (源代码复制失败) - ${duration}秒"
                return 1
            fi
        else
            log_error "无法从 kind 集群复制源代码"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log_summary "$CLUSTER_NAME: ❌ FAILED (无法获取源代码) - ${duration}秒"
            return 1
        fi
    fi
    fi  # 结束 if cluster_exists = false
    
    # 6.5. 安装 OpenEBS（对所有集群执行，无论是否已存在）
    log "检查OpenEBS安装状态..."
    
    # 检查OpenEBS是否已安装
    if kubectl --context "kind-$CLUSTER_NAME" get pods -n openebs -l name=openebs-localpv-provisioner 2>/dev/null | grep -q "Running"; then
        log_success "OpenEBS 已安装，跳过"
    else
        log "开始安装 OpenEBS..."
        if kubectl --context "kind-$CLUSTER_NAME" apply -f https://openebs.github.io/charts/openebs-operator.yaml >> "$MAIN_LOG" 2>&1; then
            docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /run/udev >> "$MAIN_LOG" 2>&1 || true
            
            # 等待 OpenEBS 就绪（最多等待60秒）
            if kubectl --context "kind-$CLUSTER_NAME" wait --for=condition=ready pod \
                -l name=openebs-localpv-provisioner \
                -n openebs \
                --timeout=60s >> "$MAIN_LOG" 2>&1; then
                log_success "OpenEBS 安装成功"
            else
                log_warning "OpenEBS 未在60秒内就绪"
                status="PARTIAL"
                error_msg="${error_msg:+$error_msg,}OpenEBS超时"
            fi
        else
            log_warning "OpenEBS 安装失败（非致命错误）"
            status="PARTIAL"
            error_msg="${error_msg:+$error_msg,}OpenEBS失败"
        fi
    fi
    
    # 7. 安装 Prometheus（对所有集群执行，无论是否已存在）
    log "检查Prometheus安装状态..."
    
    # 检查是否已安装且运行正常
    if kubectl --context "kind-$CLUSTER_NAME" get pods -n observe -l app.kubernetes.io/name=prometheus 2>/dev/null | grep -q "Running"; then
        log_success "Prometheus 已安装，跳过"
    else
        # 检查是否有残留的Helm Release
        if helm --kube-context "kind-$CLUSTER_NAME" list -n observe 2>/dev/null | grep -q "prometheus"; then
            log "发现残留的Prometheus Release，先卸载..."
            helm --kube-context "kind-$CLUSTER_NAME" uninstall prometheus -n observe >> "$MAIN_LOG" 2>&1 || true
            sleep 2
        fi
        
        log "开始安装 Prometheus..."
        
        # 创建 namespace
        kubectl --context "kind-$CLUSTER_NAME" create namespace observe >> "$MAIN_LOG" 2>&1 || true
        
        # 应用 PVC
        kubectl --context "kind-$CLUSTER_NAME" apply -f "$BASE_DIR/aiopslab/observer/prometheus/prometheus-pvc.yml" -n observe >> "$MAIN_LOG" 2>&1 || true
        
        # 安装 Prometheus（使用本地chart，已有依赖）
        if helm install prometheus "$BASE_DIR/aiopslab/observer/prometheus/prometheus" \
            -n observe \
            --kube-context "kind-$CLUSTER_NAME" \
            --create-namespace >> "$MAIN_LOG" 2>&1; then
            log_success "Prometheus 安装成功"
        else
            log_warning "Prometheus 安装失败（非致命错误）"
            status="PARTIAL"
            error_msg="${error_msg:+$error_msg,}Prometheus失败"
        fi
    fi
    
    # 8. 验证集群
    log "验证集群状态..."
    local node_status=$(kubectl --context "kind-$CLUSTER_NAME" get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$node_status" = "True" ]; then
        if [ "$cluster_exists" = true ]; then
            # 对于已存在的集群，显示Prometheus检查结果
            if [ "$status" = "SUCCESS" ]; then
                log_summary "$CLUSTER_NAME: ✅ CHECKED (Prometheus已安装) - ${duration}秒"
            else
                log_summary "$CLUSTER_NAME: ⚠️  CHECKED (已安装Prometheus) - ${duration}秒"
            fi
        else
            # 对于新创建的集群
        log_success "集群 $CLUSTER_NAME 创建完成并就绪！"
            if [ "$status" = "SUCCESS" ]; then
                log_summary "$CLUSTER_NAME: ✅ SUCCESS - ${duration}秒"
            else
                log_summary "$CLUSTER_NAME: ⚠️  PARTIAL ($error_msg) - ${duration}秒"
            fi
        fi
        return 0
    else
        log_warning "集群 $CLUSTER_NAME 状态未完全就绪"
        log_summary "$CLUSTER_NAME: ⚠️  PARTIAL (节点未就绪) - ${duration}秒"
        return 0
    fi
}

# 主执行流程
main() {
    local total_start_time=$(date +%s)
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "批量创建 Kind 集群"
    log "范围: kind$START_NUM - kind$END_NUM"
    log "总数: $((END_NUM - START_NUM + 1)) 个集群"
    log "主日志: $MAIN_LOG"
    log "状态日志: $SUMMARY_LOG"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log_summary "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_summary "Kind 集群批量创建状态"
    log_summary "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_summary "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # ===== 全局容器健康检查 =====
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔍 预检查：扫描所有Kind容器健康状态..."
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_kind_containers=$(docker ps -a --filter "name=kind" --format "{{.Names}}" 2>/dev/null || true)
    local fixed_count=0
    local healthy_count=0
    local failed_repair_count=0
    
    if [ -n "$all_kind_containers" ]; then
        while IFS= read -r container; do
            if [ -z "$container" ]; then
                continue
            fi
            
            local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            
            if [ "$status" = "running" ]; then
                ((healthy_count++))
            elif [ "$status" = "exited" ] || [ "$status" = "created" ] || [ "$status" = "paused" ]; then
                log_warning "发现异常容器: $container (状态: $status)"
                
                if docker start "$container" >> "$MAIN_LOG" 2>&1; then
                    log_success "✅ 容器 $container 已重启"
                    ((fixed_count++))
                    # 等待容器稳定
                    sleep 3
                else
                    log_error "❌ 容器 $container 重启失败"
                    ((failed_repair_count++))
                fi
            fi
        done <<< "$all_kind_containers"
        
        log ""
        log "预检查完成："
        log "  - 健康容器: $healthy_count"
        log "  - 已修复容器: $fixed_count"
        if [ $failed_repair_count -gt 0 ]; then
            log_warning "  - 修复失败: $failed_repair_count（这些集群可能会有问题）"
        fi
        log ""
    else
        log "未发现任何Kind容器"
        log ""
    fi
    
    # 统计
    local success_count=0
    local partial_count=0
    local skip_count=0
    local failed_count=0
    local failed_clusters=()
    
    # 循环创建集群
    for i in $(seq $START_NUM $END_NUM); do
        local cluster_name="kind$i"
        
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "进度: $(($i - $START_NUM + 1))/$((END_NUM - START_NUM + 1))"
        
        if create_single_cluster "$cluster_name"; then
            # 检查状态
            if grep -q "$cluster_name.*SKIP" "$SUMMARY_LOG"; then
                ((skip_count++))
            elif grep -q "$cluster_name.*PARTIAL" "$SUMMARY_LOG"; then
                ((partial_count++))
            else
            ((success_count++))
            fi
            log_success "集群 $cluster_name 完成"
        else
            ((failed_count++))
            failed_clusters+=("$cluster_name")
            log_error "集群 $cluster_name 创建失败"
        fi
        
        echo ""
    done
    
    # 清理临时备份
    rm -rf /tmp/socialNetwork_backup
    
    local total_end_time=$(date +%s)
    local total_duration=$((total_end_time - total_start_time))
    local hours=$((total_duration / 3600))
    local minutes=$(((total_duration % 3600) / 60))
    local seconds=$((total_duration % 60))
    
    # 最终统计
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "批量创建完成！"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "完全成功: $success_count 个集群"
    log "部分成功: $partial_count 个集群"
    log "跳过: $skip_count 个集群"
    log "失败: $failed_count 个集群"
    log "总耗时: ${hours}小时${minutes}分${seconds}秒"
    
    if [ $failed_count -gt 0 ]; then
        log_warning "失败的集群: ${failed_clusters[*]}"
    fi
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "所有集群列表:"
    kind get clusters | tee -a "$MAIN_LOG"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Summary 统计
    log_summary ""
    log_summary "━━━━━━━━━━ 统计 ━━━━━━━━━━"
    log_summary "完全成功: $success_count"
    log_summary "部分成功: $partial_count"
    log_summary "跳过: $skip_count"
    log_summary "失败: $failed_count"
    log_summary "总耗时: ${hours}小时${minutes}分${seconds}秒"
    log_summary "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_summary "━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 执行
main
