#!/bin/bash

# =============================================================================
# 后台启动 Docker 迁移脚本
# =============================================================================

cd /home/ecs-user/projects/AI_SRE_Playground-echo/cwy-docker

# 预先获取 sudo 权限（避免后台运行时等待密码）
echo "请输入 sudo 密码以开始迁移..."
sudo -v

if [ $? -ne 0 ]; then
    echo "❌ sudo 权限验证失败"
    exit 1
fi

# 后台运行迁移脚本
echo "🚀 开始后台运行 Docker 迁移..."
nohup ./migrate_docker_to_data.sh > ../logs/docker/migration_console.log 2>&1 &

MIGRATION_PID=$!
echo "$MIGRATION_PID" > ../logs/docker/migration.pid

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 迁移已在后台启动"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 进程 ID: $MIGRATION_PID"
echo "📋 控制台日志: logs/docker/migration_console.log"
echo "📋 详细日志: logs/docker/docker_migration_*.log"
echo ""
echo "🔍 监控命令:"
echo "   # 查看实时日志"
echo "   tail -f logs/docker/migration_console.log"
echo ""
echo "   # 查看进程状态"
echo "   ps aux | grep $MIGRATION_PID"
echo ""
echo "   # 检查是否完成"
echo "   tail -20 logs/docker/migration_console.log"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

