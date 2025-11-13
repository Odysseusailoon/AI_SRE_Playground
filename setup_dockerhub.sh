#!/usr/bin/env bash
set -e

DOCKER_USERNAME="${1:-${DOCKER_USERNAME}}"
DOCKER_PASSWORD="${2:-${DOCKER_PASSWORD}}"
DOCKER_EMAIL="${3:-${DOCKER_EMAIL:-user@example.com}}"

NAMESPACES=("openebs" "observe" "test-hotel-reservation" "chaos-mesh")

echo "配置 Docker Hub 认证..."

# 登录
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

# 配置 kind 节点
KIND_NODES=$(docker ps --filter "name=kind" --format "{{.Names}}")
for node in $KIND_NODES; do
    docker exec $node mkdir -p /root/.docker 2>/dev/null || true
    docker cp ~/.docker/config.json $node:/root/.docker/config.json
    docker exec $node chmod 600 /root/.docker/config.json
    echo "✓ $node 配置完成"
done

# 配置 namespace
for NAMESPACE in "${NAMESPACES[@]}"; do
    echo "配置 namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" 2>/dev/null || true
    
    kubectl delete secret dockerhub-secret -n "$NAMESPACE" 2>/dev/null || true
    kubectl create secret docker-registry dockerhub-secret \
      --docker-server=https://index.docker.io/v1/ \
      --docker-username="$DOCKER_USERNAME" \
      --docker-password="$DOCKER_PASSWORD" \
      --docker-email="$DOCKER_EMAIL" \
      -n "$NAMESPACE"
    
    kubectl patch serviceaccount default -n "$NAMESPACE" \
      -p '{"imagePullSecrets": [{"name": "dockerhub-secret"}]}'
    
    echo "✓ $NAMESPACE 配置完成"
done

echo "✅ 所有配置完成！"
