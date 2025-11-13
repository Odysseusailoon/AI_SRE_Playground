#!/bin/bash
# 自动拉取所有 AIOpsLab 任务需要的镜像并加载到 kind

set -e

PROJECT_ROOT="/home/ecs-user/projects/AI_SRE_Playground-echo"
IMAGES_FILE="$PROJECT_ROOT/kind/images.txt"

echo "=== AIOpsLab 完整镜像准备脚本 ==="
echo "镜像列表: $IMAGES_FILE"
echo ""

if [ ! -f "$IMAGES_FILE" ]; then
    echo "❌ 找不到 $IMAGES_FILE"
    exit 1
fi

# 读取镜像列表
mapfile -t IMAGES < "$IMAGES_FILE"
TOTAL=${#IMAGES[@]}
echo "共 $TOTAL 个镜像"
echo ""

# 统计已存在的
EXISTING=0
echo "检查已存在的镜像..."
for img in "${IMAGES[@]}"; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${img}$" 2>/dev/null; then
        ((EXISTING++))
    fi
done
NEEDED=$((TOTAL - EXISTING))
echo "✓ 已存在: $EXISTING/$TOTAL"
echo "↓ 需下载: $NEEDED/$TOTAL"
echo ""

if [ $NEEDED -eq 0 ]; then
    echo "✅ 所有镜像已准备好！"
    exit 0
fi

# 并行下载（限制并发数）
MAX_PARALLEL=5
echo "开始下载缺失镜像（最多 $MAX_PARALLEL 并行）..."
DOWNLOADED=0
for img in "${IMAGES[@]}"; do
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${img}$" 2>/dev/null; then
        echo "⬇ [$((++DOWNLOADED))/$NEEDED] $img"
        docker pull "$img" &
        
        # 控制并发数
        if [[ $(jobs -r -p | wc -l) -ge $MAX_PARALLEL ]]; then
            wait -n
        fi
    fi
done
wait
echo "✅ 所有镜像下载完成！"
echo ""

# 加载到 kind
echo "加载到 kind 集群（这可能需要几分钟）..."
for img in "${IMAGES[@]}"; do
    kind load docker-image "$img" --name kind 2>/dev/null || true
done

echo ""
echo "✅ 完成！所有镜像已准备好，可以开始训练了！"
