#!/bin/bash

# =============================================================================
# Docker 数据目录迁移脚本
# 将 Docker 从 /var/lib/docker 迁移到 /data/docker
# =============================================================================

set -e

LOG_FILE="/home/ecs-user/projects/AI_SRE_Playground-echo/logs/docker/docker_migration_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# 错误处理
error_exit() {
    log_error "$1"
    log_error "迁移失败！Docker 服务将尝试恢复..."
    sudo systemctl start docker || true
    exit 1
}

# 主执行流程
main() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Docker 数据目录迁移"
    log "从: /var/lib/docker"
    log "到: /data/docker"
    log "日志: $LOG_FILE"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 0. 检查权限
    log_info "检查 sudo 权限..."
    if ! sudo -n true 2>/dev/null; then
        error_exit "需要 sudo 权限，请先运行 sudo -v"
    fi
    log_success "权限检查通过"
    
    # 1. 检查当前状态
    log_info "检查当前 Docker 状态..."
    CURRENT_ROOT=$(sudo docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
    log "当前 Docker Root Dir: $CURRENT_ROOT"
    
    if [ "$CURRENT_ROOT" = "/data/docker" ]; then
        log_warning "Docker 已经在 /data/docker，无需迁移"
        exit 0
    fi
    
    if [ ! -d "/var/lib/docker" ]; then
        error_exit "/var/lib/docker 目录不存在"
    fi
    
    # 2. 检查磁盘空间
    log_info "检查磁盘空间..."
    DOCKER_SIZE=$(sudo du -sb /var/lib/docker | awk '{print $1}')
    DATA_AVAIL=$(df /data | tail -1 | awk '{print $4}')
    DATA_AVAIL_BYTES=$((DATA_AVAIL * 1024))
    
    log "Docker 数据大小: $(numfmt --to=iec-i --suffix=B $DOCKER_SIZE 2>/dev/null || echo "$DOCKER_SIZE bytes")"
    log "/data 可用空间: $(numfmt --to=iec-i --suffix=B $DATA_AVAIL_BYTES 2>/dev/null || echo "$DATA_AVAIL_BYTES bytes")"
    
    if [ $DATA_AVAIL_BYTES -lt $DOCKER_SIZE ]; then
        error_exit "/data 空间不足"
    fi
    log_success "磁盘空间充足"
    
    # 3. 记录当前运行的容器
    log_info "记录当前运行的容器..."
    RUNNING_CONTAINERS=$(sudo docker ps -q)
    CONTAINER_COUNT=$(echo "$RUNNING_CONTAINERS" | grep -c . || echo 0)
    log "运行中的容器数量: $CONTAINER_COUNT"
    
    if [ $CONTAINER_COUNT -gt 0 ]; then
        echo "$RUNNING_CONTAINERS" > /tmp/docker_running_containers.txt
        log "容器列表已保存到 /tmp/docker_running_containers.txt"
    fi
    
    # 4. 停止 Docker 服务
    log_info "停止 Docker 服务..."
    sudo systemctl stop docker || error_exit "无法停止 Docker 服务"
    
    # 确保完全停止
    sleep 3
    
    if sudo systemctl is-active --quiet docker; then
        error_exit "Docker 服务未能完全停止"
    fi
    log_success "Docker 服务已停止"
    
    # 5. 检查目标目录
    log_info "准备目标目录..."
    if [ -d "/data/docker" ]; then
        log_warning "/data/docker 已存在，将备份为 /data/docker.backup.$(date +%s)"
        sudo mv /data/docker /data/docker.backup.$(date +%s)
    fi
    
    # 6. 迁移数据
    log_info "开始迁移数据（这可能需要几分钟）..."
    START_TIME=$(date +%s)
    
    # 使用 rsync 迁移（支持断点续传）
    if command -v rsync >/dev/null 2>&1; then
        log "使用 rsync 迁移..."
        sudo rsync -aP --info=progress2 /var/lib/docker/ /data/docker/ 2>&1 | tee -a "$LOG_FILE" || error_exit "数据迁移失败"
    else
        log "使用 cp 迁移..."
        sudo cp -a /var/lib/docker /data/docker || error_exit "数据迁移失败"
    fi
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log_success "数据迁移完成（耗时: ${DURATION}秒）"
    
    # 7. 验证迁移
    log_info "验证迁移数据..."
    if [ ! -d "/data/docker" ]; then
        error_exit "迁移失败：/data/docker 不存在"
    fi
    
    DATA_DOCKER_SIZE=$(sudo du -sb /data/docker 2>/dev/null | awk '{print $1}' || echo 0)
    log "原目录大小: $(numfmt --to=iec-i --suffix=B $DOCKER_SIZE 2>/dev/null || echo "$DOCKER_SIZE bytes")"
    log "新目录大小: $(numfmt --to=iec-i --suffix=B $DATA_DOCKER_SIZE 2>/dev/null || echo "$DATA_DOCKER_SIZE bytes")"
    
    # 8. 备份原目录
    log_info "备份原目录..."
    sudo mv /var/lib/docker /var/lib/docker.backup.$(date +%s) || error_exit "无法备份原目录"
    log_success "原目录已备份"
    
    # 9. 创建软链接
    log_info "创建软链接..."
    sudo ln -s /data/docker /var/lib/docker || error_exit "无法创建软链接"
    
    if [ ! -L "/var/lib/docker" ]; then
        error_exit "软链接创建失败"
    fi
    log_success "软链接创建成功: /var/lib/docker -> /data/docker"
    
    # 10. 启动 Docker 服务
    log_info "启动 Docker 服务..."
    sudo systemctl start docker || error_exit "无法启动 Docker 服务"
    
    # 等待 Docker 完全启动
    sleep 5
    
    if ! sudo systemctl is-active --quiet docker; then
        error_exit "Docker 服务启动失败"
    fi
    log_success "Docker 服务已启动"
    
    # 11. 验证新路径
    log_info "验证 Docker Root Dir..."
    NEW_ROOT=$(sudo docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
    log "新的 Docker Root Dir: $NEW_ROOT"
    
    if [ "$NEW_ROOT" != "/data/docker" ]; then
        log_warning "Docker Root Dir 仍然是 $NEW_ROOT，但软链接已生效"
    fi
    
    # 12. 重启之前运行的容器
    if [ -f /tmp/docker_running_containers.txt ] && [ $CONTAINER_COUNT -gt 0 ]; then
        log_info "重启之前运行的容器..."
        RESTARTED=0
        FAILED=0
        
        while IFS= read -r container_id; do
            if [ -n "$container_id" ]; then
                if sudo docker start "$container_id" >/dev/null 2>&1; then
                    ((RESTARTED++))
                else
                    ((FAILED++))
                    log_warning "容器 $container_id 启动失败"
                fi
            fi
        done < /tmp/docker_running_containers.txt
        
        log "容器重启: $RESTARTED 成功, $FAILED 失败"
        rm -f /tmp/docker_running_containers.txt
    fi
    
    # 13. 验证 Kind 集群
    log_info "验证 Kind 集群..."
    CLUSTERS=$(kind get clusters 2>/dev/null || echo "")
    if [ -n "$CLUSTERS" ]; then
        CLUSTER_COUNT=$(echo "$CLUSTERS" | wc -l)
        log "发现 $CLUSTER_COUNT 个 Kind 集群"
        echo "$CLUSTERS" | tee -a "$LOG_FILE"
        
        # 检查第一个集群的节点状态
        FIRST_CLUSTER=$(echo "$CLUSTERS" | head -1)
        log "检查集群 $FIRST_CLUSTER 状态..."
        if kubectl --context "kind-$FIRST_CLUSTER" get nodes >/dev/null 2>&1; then
            log_success "Kind 集群工作正常"
        else
            log_warning "Kind 集群可能需要重启"
        fi
    else
        log "未发现 Kind 集群"
    fi
    
    # 14. 最终状态报告
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "迁移完成！"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log "📊 最终状态:"
    log "  Docker Root Dir: $NEW_ROOT"
    log "  软链接: /var/lib/docker -> /data/docker"
    log "  迁移耗时: ${DURATION}秒"
    log "  数据大小: $(numfmt --to=iec-i --suffix=B $DATA_DOCKER_SIZE 2>/dev/null || echo "$DATA_DOCKER_SIZE bytes")"
    
    echo ""
    log "📋 磁盘使用情况:"
    df -h | grep -E "Filesystem|/data|vda3" | tee -a "$LOG_FILE"
    
    echo ""
    log "🎉 现在可以创建新的 Kind 集群了！"
    log "   所有新集群将自动使用 /data 的 2TB 空间"
    
    echo ""
    log "💡 提示:"
    log "  - 备份的原目录: /var/lib/docker.backup.*"
    log "  - 确认一切正常后，可以删除备份以释放空间:"
    log "    sudo rm -rf /var/lib/docker.backup.*"
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 执行
main

