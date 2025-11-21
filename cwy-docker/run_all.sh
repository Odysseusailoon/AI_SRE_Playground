#!/bin/bash

# =============================================================================
# 一键执行：Docker 迁移 + Kind 集群批量创建
# =============================================================================

cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Docker 迁移 + Kind 集群批量创建"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. 启动 Docker 迁移
echo "【步骤 1/2】启动 Docker 迁移..."
./start_migration.sh

if [ $? -ne 0 ]; then
    echo "❌ Docker 迁移启动失败"
    exit 1
fi

echo ""
echo "⏳ 等待 Docker 迁移完成..."
echo "   提示：可以在另一个终端运行 ./monitor_migration.sh 查看进度"
echo ""

# 等待迁移进程完成
MIGRATION_PID=$(cat ../logs/docker/migration.pid 2>/dev/null)
if [ -n "$MIGRATION_PID" ]; then
    while ps -p $MIGRATION_PID > /dev/null 2>&1; do
        sleep 10
        echo "   [$(date '+%H:%M:%S')] Docker 迁移进行中..."
    done
fi

echo ""
echo "✅ Docker 迁移完成！"
echo ""

# 验证迁移结果
DOCKER_ROOT=$(sudo docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
echo "📊 验证结果:"
echo "   Docker Root Dir: $DOCKER_ROOT"

if [ "$DOCKER_ROOT" = "/data/docker" ] || [ -L "/var/lib/docker" ]; then
    echo "   ✅ Docker 已成功迁移到 /data"
else
    echo "   ⚠️  Docker 可能未完全迁移，请检查日志"
    echo "   继续创建 Kind 集群..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "按 Enter 继续创建 Kind 集群 (kind11-kind86)，或 Ctrl+C 取消..." 

# 2. 创建 Kind 集群
echo ""
echo "【步骤 2/2】开始批量创建 Kind 集群..."
echo ""

./create_kinds_11_to_86.sh

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 所有任务完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 最终状态:"
echo "   Kind 集群总数: $(kind get clusters 2>/dev/null | wc -l)"
echo ""
echo "📋 日志位置:"
echo "   - Docker 迁移日志: ../logs/docker/docker_migration_*.log"
echo "   - Kind 创建日志: ../logs/docker/kind_creation/batch_creation_*.log"
echo ""

