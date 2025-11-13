# 快速创建 Kind 集群完整指南

本文档提供创建新 Kind 集群（如 kind4, kind5 等）的完整流程。

## 📋 目录

1. [前置条件](#前置条件)
2. [快速开始](#快速开始)
3. [详细步骤](#详细步骤)
4. [故障排查](#故障排查)
5. [验证检查](#验证检查)

---

## 前置条件

### 必需组件

- ✅ Docker 运行中
- ✅ Kind 已安装
- ✅ kubectl 已安装
- ✅ Helm 已安装
- ✅ 原 `kind` 集群存在（用于复制源代码）

### 必需镜像（宿主机上）

所有必需的 200+ 镜像应该已经在宿主机本地，包括：

- **基础设施镜像**:
  - OpenEBS: `openebs/provisioner-localpv:3.4.0`, `openebs/linux-utils:3.5.0` 等
  - Prometheus: `quay.io/prometheus/*` 系列
  - 工具镜像: `alpine/git:latest`

- **应用镜像**:
  - Social Network: `deathstarbench/social-network-microservices:latest`
  - 数据库: `mongo:4.4.6`, `redis:6.2.4`, `memcached:1.6.7`
  - 其他组件: `jaegertracing/all-in-one:1.57` 等

可以运行 `docker images` 检查本地镜像。

---

## 快速开始

### 一键创建集群

```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo

# 创建 kind4 集群（自动完成所有配置）
./create_new_kind_cluster.sh kind4

# 或者在后台运行
nohup ./create_new_kind_cluster.sh kind4 > logs/kind4_creation.log 2>&1 &
```

**预计时间**: 3-5 分钟

**完成后**:
- ✅ 集群创建并运行
- ✅ 所有镜像已加载
- ✅ OpenEBS 已安装并运行
- ✅ Prometheus 已安装并运行
- ✅ socialNetwork 源代码已复制
- ✅ 集群就绪可用

---

## 详细步骤

如果你想手动执行或理解每个步骤，以下是完整流程。

### 步骤 1: 创建 Kind 集群

```bash
# 集群名称
CLUSTER_NAME="kind4"

# 创建集群
kind create cluster --name $CLUSTER_NAME

# 验证集群
kubectl --context kind-$CLUSTER_NAME get nodes
```

**预期输出**:
```
NAME                   STATUS   ROLES           AGE   VERSION
kind4-control-plane    Ready    control-plane   30s   v1.27.3
```

---

### 步骤 2: 加载必需的镜像

#### 2.1 加载应用镜像

```bash
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

# 加载镜像到集群
for image in "${APP_IMAGES[@]}"; do
    echo "加载: $image"
    kind load docker-image $image --name $CLUSTER_NAME
done
```

#### 2.2 加载 OpenEBS 镜像

```bash
OPENEBS_IMAGES=(
    "openebs/provisioner-localpv:3.4.0"
    "openebs/linux-utils:3.5.0"
    "openebs/node-disk-exporter:2.1.0"
    "openebs/node-disk-operator:2.1.0"
    "openebs/node-disk-manager:2.1.0"
)

for image in "${OPENEBS_IMAGES[@]}"; do
    echo "加载: $image"
    kind load docker-image $image --name $CLUSTER_NAME
done
```

#### 2.3 加载 Prometheus 镜像

```bash
PROMETHEUS_IMAGES=(
    "quay.io/prometheus/blackbox-exporter:v0.24.0"
    "quay.io/prometheus/node-exporter:v1.6.1"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0"
    "quay.io/prometheus/prometheus:v2.47.2"
    "quay.io/prometheus/pushgateway:v1.6.2"
    "registry.cn-wulanchabu.aliyuncs.com/moge1/kube-state-metrics:v2.3.0"
)

for image in "${PROMETHEUS_IMAGES[@]}"; do
    echo "加载: $image"
    kind load docker-image $image --name $CLUSTER_NAME
done
```

---

### 步骤 3: 安装 OpenEBS

```bash
# 安装 OpenEBS
kubectl --context kind-$CLUSTER_NAME apply -f https://openebs.github.io/charts/openebs-operator.yaml

# 创建必需的目录
docker exec ${CLUSTER_NAME}-control-plane mkdir -p /run/udev

# 等待 OpenEBS 就绪
kubectl --context kind-$CLUSTER_NAME wait --for=condition=ready pod \
  -l name=openebs-localpv-provisioner \
  -n openebs \
  --timeout=300s

echo "✅ OpenEBS 安装完成"
```

---

### 步骤 4: 安装 Prometheus

```bash
# 创建 observe 命名空间
kubectl --context kind-$CLUSTER_NAME create namespace observe

# 添加 Helm repo（如果未添加）
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 安装 Prometheus
helm --kube-context kind-$CLUSTER_NAME install prometheus \
  prometheus-community/prometheus \
  -n observe

# 等待 Prometheus 就绪
kubectl --context kind-$CLUSTER_NAME wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus,component=server \
  -n observe \
  --timeout=300s

echo "✅ Prometheus 安装完成"
```

---

### 步骤 5: 复制 socialNetwork 源代码

这是**关键步骤**！许多应用的 init container 需要这些源代码文件。

```bash
# 从原 kind 集群复制源代码
echo "📦 复制 socialNetwork 源代码..."

# 步骤 1: 从原集群导出到临时目录
docker cp kind-control-plane:/var/lib/kubelet/hostpath/socialNetwork /tmp/socialNetwork

# 步骤 2: 导入到新集群
docker cp /tmp/socialNetwork ${CLUSTER_NAME}-control-plane:/var/lib/kubelet/hostpath/

# 步骤 3: 清理临时文件
rm -rf /tmp/socialNetwork

echo "✅ 源代码复制完成"
```

**重要说明**: 
- `media-frontend` 需要 `/var/lib/kubelet/hostpath/socialNetwork/media-frontend/lua-scripts/*`
- `nginx-thrift` 需要 `/var/lib/kubelet/hostpath/socialNetwork/gen-lua/*`
- 不复制这些文件，相关 Pod 的 init container 会失败

---

### 步骤 6: 验证集群状态

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 集群验证：$CLUSTER_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 节点状态
echo "【节点状态】"
kubectl --context kind-$CLUSTER_NAME get nodes

# OpenEBS 状态
echo "【OpenEBS 状态】"
kubectl --context kind-$CLUSTER_NAME get pods -n openebs

# Prometheus 状态
echo "【Prometheus 状态】"
kubectl --context kind-$CLUSTER_NAME get pods -n observe

# 统计
TOTAL_PODS=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | wc -l)
RUNNING_PODS=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | grep -c "Running")

echo "【汇总】"
echo "  总 Pods: $TOTAL_PODS"
echo "  运行中: $RUNNING_PODS"
```

---

## 故障排查

### 问题 1: OpenEBS NDM Pod 一直 ContainerCreating

**症状**: `openebs-ndm-xxx` 状态为 `ContainerCreating`

**原因**: 缺少 `/run/udev` 目录

**解决方案**:
```bash
docker exec ${CLUSTER_NAME}-control-plane mkdir -p /run/udev
kubectl --context kind-$CLUSTER_NAME delete pod -n openebs -l app=openebs-ndm
```

---

### 问题 2: media-frontend 或 nginx-thrift Pod Init:Error

**症状**: Pod 状态为 `Init:Error`, 日志显示 `No such file or directory`

**原因**: 缺少 socialNetwork 源代码文件

**解决方案**:
```bash
# 重新复制源代码
docker cp kind-control-plane:/var/lib/kubelet/hostpath/socialNetwork /tmp/socialNetwork
docker cp /tmp/socialNetwork ${CLUSTER_NAME}-control-plane:/var/lib/kubelet/hostpath/
rm -rf /tmp/socialNetwork

# 删除失败的 Pod 让它们重建
kubectl --context kind-$CLUSTER_NAME delete pod -n test-social-network \
  -l app=media-frontend
kubectl --context kind-$CLUSTER_NAME delete pod -n test-social-network \
  -l app=nginx-thrift
```

---

### 问题 3: 镜像拉取失败 ImagePullBackOff

**症状**: Pod 状态为 `ImagePullBackOff` 或 `ErrImagePull`

**原因**: 镜像未加载到集群

**解决方案**:
```bash
# 检查缺失的镜像
kubectl --context kind-$CLUSTER_NAME describe pod <pod-name> -n <namespace> | grep "Failed"

# 加载镜像
kind load docker-image <image-name> --name $CLUSTER_NAME

# 如果宿主机也没有镜像，需要先 pull
docker pull <image-name>
kind load docker-image <image-name> --name $CLUSTER_NAME
```

---

### 问题 4: kube-proxy CrashLoopBackOff (too many open files)

**症状**: `kube-proxy` 频繁重启，日志显示 "too many open files"

**原因**: `inotify` 限制太低

**解决方案**:
```bash
# 在宿主机上增加限制
sudo sysctl -w fs.inotify.max_user_instances=512
sudo sysctl -w fs.inotify.max_user_watches=524288

# 重启 kube-proxy
kubectl --context kind-$CLUSTER_NAME delete pod -n kube-system -l k8s-app=kube-proxy

# 永久生效（可选）
echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
```

---

## 验证检查

### 完整健康检查脚本

```bash
#!/bin/bash

CLUSTER_NAME="kind4"  # 修改为你的集群名

echo "🔍 健康检查: $CLUSTER_NAME"
echo ""

# 1. 节点检查
echo "1️⃣  节点状态:"
kubectl --context kind-$CLUSTER_NAME get nodes

# 2. 所有 Pods 检查
echo ""
echo "2️⃣  所有 Pods 状态:"
kubectl --context kind-$CLUSTER_NAME get pods -A

# 3. 统计
echo ""
echo "3️⃣  统计信息:"
TOTAL=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | wc -l)
RUNNING=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | grep -c "Running")
PENDING=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | grep -c "Pending")
ERROR=$(kubectl --context kind-$CLUSTER_NAME get pods -A --no-headers | grep -cE "Error|CrashLoop|ImagePull")

echo "  总 Pods: $TOTAL"
echo "  运行中: $RUNNING"
echo "  等待中: $PENDING"
echo "  错误: $ERROR"

# 4. StorageClass 检查
echo ""
echo "4️⃣  StorageClass:"
kubectl --context kind-$CLUSTER_NAME get sc

# 5. 源代码文件检查
echo ""
echo "5️⃣  socialNetwork 源代码:"
docker exec ${CLUSTER_NAME}-control-plane ls -la /var/lib/kubelet/hostpath/socialNetwork/ | head -10

echo ""
if [ "$RUNNING" -eq "$TOTAL" ] && [ "$ERROR" -eq 0 ]; then
    echo "✅ 集群状态健康！"
else
    echo "⚠️  集群存在问题，请检查上述输出"
fi
```

---

## 快速命令参考

### 集群管理

```bash
# 查看所有集群
kind get clusters

# 删除集群
kind delete cluster --name kind4

# 切换 kubectl 上下文
kubectl config use-context kind-kind4
```

### 常用检查命令

```bash
# 查看特定集群的 Pods
kubectl --context kind-kind4 get pods -A

# 查看特定命名空间
kubectl --context kind-kind4 get pods -n test-social-network

# 查看 Pod 日志
kubectl --context kind-kind4 logs <pod-name> -n <namespace>

# 进入 Pod
kubectl --context kind-kind4 exec -it <pod-name> -n <namespace> -- /bin/sh

# 查看 Pod 详细信息
kubectl --context kind-kind4 describe pod <pod-name> -n <namespace>
```

### 镜像管理

```bash
# 查看宿主机镜像
docker images

# 查看集群内镜像
docker exec kind4-control-plane crictl images

# 加载镜像到集群
kind load docker-image <image-name> --name kind4

# 批量加载镜像
./load_all_app_images.sh kind4
```

---

## 附录

### 完整镜像清单

可以参考 `/home/ecs-user/projects/AI_SRE_Playground-echo/docs-cwy/完整镜像清单.md`

### 相关脚本

- `create_new_kind_cluster.sh` - 一键创建集群
- `load_all_app_images.sh` - 批量加载应用镜像  
- `verify_cluster_health.sh` - 集群健康检查

### 预计资源消耗

单个 Kind 集群（未部署应用）：
- **CPU**: ~0.5 核
- **内存**: ~1.5 GB
- **磁盘**: ~2 GB

部署 Social Network 应用后：
- **CPU**: ~2-3 核
- **内存**: ~4-6 GB
- **磁盘**: ~3-4 GB

---

## 总结

创建新 Kind 集群的关键步骤：

1. ✅ 创建集群
2. ✅ 加载所有必需镜像（应用 + OpenEBS + Prometheus + 工具）
3. ✅ 安装 OpenEBS 并创建 `/run/udev`
4. ✅ 安装 Prometheus
5. ✅ **复制 socialNetwork 源代码**（重要！）
6. ✅ 验证集群健康

使用 `create_new_kind_cluster.sh` 可以自动完成所有步骤！

---

**创建时间**: 2025-11-12  
**版本**: 1.0  
**维护者**: AI SRE Team

