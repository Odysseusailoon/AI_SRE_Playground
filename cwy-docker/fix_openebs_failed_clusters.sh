#!/bin/bash
set -e

# ==========================================
# OpenEBS 修复脚本
# 用途：修复批量创建时 OpenEBS 安装失败的集群
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志目录
LOG_DIR="/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/kind_creation"
REPAIR_LOG="$LOG_DIR/openebs_repair.log"
REPAIR_SUMMARY="$LOG_DIR/openebs_repair_summary.log"

# 需要修复的集群列表（OpenEBS失败的26个集群）
FAILED_CLUSTERS=(
    kind12 kind15 kind21 kind24 kind27 kind29 kind32 kind35 kind36 kind37
    kind39 kind48 kind49 kind50 kind51 kind53 kind56 kind64 kind66 kind67
    kind69 kind70 kind72 kind74 kind78 kind86
)

# 日志函数
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$REPAIR_LOG"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$REPAIR_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$REPAIR_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$REPAIR_LOG"
}

# 等待 API Server 完全就绪
wait_for_api_server() {
    local cluster_name=$1
    local max_attempts=30
    local attempt=0
    
    log "等待 $cluster_name API Server 完全就绪..."
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl get nodes --context "kind-${cluster_name}" &>/dev/null; then
            # API Server 可访问，再等待节点就绪
            if kubectl wait --for=condition=Ready nodes --all --timeout=60s --context "kind-${cluster_name}" &>/dev/null; then
                log_success "API Server 已就绪"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    log_error "API Server 等待超时"
    return 1
}

# 安装 OpenEBS
install_openebs() {
    local cluster_name=$1
    local max_retries=3
    local retry=0
    
    log "开始安装 OpenEBS 到 $cluster_name..."
    
    while [ $retry -lt $max_retries ]; do
        if [ $retry -gt 0 ]; then
            log_warning "重试第 $retry 次..."
            sleep 5
        fi
        
        # 尝试安装 OpenEBS
        if kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml \
            --context "kind-${cluster_name}" \
            --request-timeout=60s >> "$REPAIR_LOG" 2>&1; then
            
            log_success "OpenEBS 资源创建成功"
            
            # 等待 OpenEBS 组件就绪
            log "等待 OpenEBS 组件启动..."
            sleep 10
            
            # 验证 OpenEBS 安装
            if kubectl get pods -n openebs --context "kind-${cluster_name}" &>/dev/null; then
                log_success "OpenEBS 安装成功！"
                return 0
            else
                log_warning "OpenEBS namespace 未找到"
            fi
        else
            log_warning "OpenEBS 安装命令执行失败"
        fi
        
        retry=$((retry + 1))
    done
    
    log_error "OpenEBS 安装失败（已重试 $max_retries 次）"
    return 1
}

# 验证 OpenEBS 状态
verify_openebs() {
    local cluster_name=$1
    
    log "验证 $cluster_name OpenEBS 状态..."
    
    # 检查 OpenEBS namespace
    if ! kubectl get namespace openebs --context "kind-${cluster_name}" &>/dev/null; then
        log_error "OpenEBS namespace 不存在"
        return 1
    fi
    
    # 检查 OpenEBS pods
    local pod_count=$(kubectl get pods -n openebs --context "kind-${cluster_name}" --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -eq 0 ]; then
        log_error "OpenEBS 没有运行的 Pod"
        return 1
    fi
    
    # 检查 StorageClass
    local sc_count=$(kubectl get storageclass --context "kind-${cluster_name}" --no-headers 2>/dev/null | grep openebs | wc -l)
    if [ "$sc_count" -gt 0 ]; then
        log_success "OpenEBS StorageClass 已创建 (数量: $sc_count)"
    else
        log_warning "未找到 OpenEBS StorageClass"
    fi
    
    log_success "验证完成"
    return 0
}

# 修复单个集群
repair_single_cluster() {
    local cluster_name=$1
    local start_time=$(date +%s)
    
    echo "" >> "$REPAIR_LOG"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "开始修复集群: $cluster_name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 检查集群是否存在
    if ! kind get clusters 2>/dev/null | grep -q "^${cluster_name}$"; then
        log_error "集群 $cluster_name 不存在"
        echo "[$(date '+%H:%M:%S')] $cluster_name: ❌ FAILED (集群不存在)" >> "$REPAIR_SUMMARY"
        return 1
    fi
    
    # 等待 API Server 就绪
    if ! wait_for_api_server "$cluster_name"; then
        local duration=$(($(date +%s) - start_time))
        echo "[$(date '+%H:%M:%S')] $cluster_name: ❌ FAILED (API Server 超时) - ${duration}秒" >> "$REPAIR_SUMMARY"
        return 1
    fi
    
    # 安装 OpenEBS
    if install_openebs "$cluster_name"; then
        # 验证安装
        if verify_openebs "$cluster_name"; then
            local duration=$(($(date +%s) - start_time))
            log_success "集群 $cluster_name 修复成功！"
            echo "[$(date '+%H:%M:%S')] $cluster_name: ✅ SUCCESS - ${duration}秒" >> "$REPAIR_SUMMARY"
            return 0
        fi
    fi
    
    local duration=$(($(date +%s) - start_time))
    log_error "集群 $cluster_name 修复失败"
    echo "[$(date '+%H:%M:%S')] $cluster_name: ❌ FAILED - ${duration}秒" >> "$REPAIR_SUMMARY"
    return 1
}

# 主函数
main() {
    local start_time=$(date +%s)
    local success_count=0
    local failed_count=0
    local total_count=${#FAILED_CLUSTERS[@]}
    
    # 初始化日志
    cat > "$REPAIR_SUMMARY" << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OpenEBS 修复任务
开始时间: $(date '+%Y-%m-%d %H:%M:%S')
需要修复的集群数量: $total_count
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    
    log "=========================================="
    log "OpenEBS 批量修复脚本启动"
    log "需要修复的集群数量: $total_count"
    log "=========================================="
    echo ""
    
    # 遍历修复所有失败的集群
    local index=0
    for cluster in "${FAILED_CLUSTERS[@]}"; do
        index=$((index + 1))
        
        log ""
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "进度: $index/$total_count"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if repair_single_cluster "$cluster"; then
            success_count=$((success_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
        
        # 显示当前进度
        log "当前进度: 成功 $success_count, 失败 $failed_count, 剩余 $((total_count - index))"
    done
    
    # 计算总耗时
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local hours=$((total_duration / 3600))
    local minutes=$(((total_duration % 3600) / 60))
    local seconds=$((total_duration % 60))
    
    # 输出最终统计
    cat >> "$REPAIR_SUMMARY" << EOF

━━━━━━━━━━ 修复统计 ━━━━━━━━━━
修复成功: $success_count
修复失败: $failed_count
总耗时: ${hours}小时${minutes}分${seconds}秒
完成时间: $(date '+%Y-%m-%d %H:%M:%S')
━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    
    echo ""
    log "=========================================="
    log "OpenEBS 修复任务完成"
    log "修复成功: $success_count/$total_count"
    log "修复失败: $failed_count/$total_count"
    log "总耗时: ${hours}小时${minutes}分${seconds}秒"
    log "=========================================="
    
    # 如果有失败，返回非零退出码
    if [ $failed_count -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# 执行主函数
main

