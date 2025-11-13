#!/bin/bash
# 预拉取所有 AIOpsLab 需要的镜像并加载到 kind

set -e

echo "=== AIOpsLab 镜像准备脚本 ==="
echo ""

# 所有镜像列表
IMAGES=(
  # 基础设施
  "ghcr.io/chaos-mesh/chaos-mesh:v2.6.2"
  "ghcr.io/chaos-mesh/chaos-daemon:v2.6.2"
  "ghcr.io/chaos-mesh/chaos-dashboard:v2.6.2"
  "ghcr.io/chaos-mesh/chaos-coredns:v0.2.6"
  "openebs/provisioner-localpv:3.4.0"
  "openebs/node-disk-operator:2.1.0"
  "openebs/node-disk-exporter:2.1.0"
  "openebs/linux-utils:3.5.0"
  
  # Prometheus
  "quay.io/prometheus/prometheus:v2.47.2"
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0"
  "quay.io/prometheus/pushgateway:v1.6.2"
  "quay.io/prometheus/node-exporter:v1.6.1"
  "quay.io/prometheus/blackbox-exporter:v0.24.0"
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.0"
  
  # Hotel Reservation
  "yinfangchen/hotelreservation:latest"
  "docker.io/mongo:4.4.6"
  "docker.io/memcached:latest"
  "docker.io/consul:latest"
  "jaegertracing/all-in-one:1.57"
)

TOTAL=${#IMAGES[@]}
echo "需要准备 $TOTAL 个镜像"
echo ""

# 检查已存在的
EXISTING=0
for img in "${IMAGES[@]}"; do
  if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${img}$"; then
    ((EXISTING++))
  fi
done
echo "已存在: $EXISTING/$TOTAL"
echo ""

# 下载缺失的
echo "开始下载缺失的镜像（并行）..."
for img in "${IMAGES[@]}"; do
  if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${img}$"; then
    echo "⬇ $img"
    docker pull "$img" &
  fi
done

wait
echo "✅ 所有镜像下载完成"
echo ""

# 加载到 kind
echo "加载到 kind 集群..."
for img in "${IMAGES[@]}"; do
  echo "⬆ $img"
  kind load docker-image "$img" --name kind 2>/dev/null || true
done

echo ""
echo "✅ 所有镜像已准备完成！"
