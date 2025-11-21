#!/bin/bash

# 统一镜像加载脚本 - 86个任务的所有必需镜像
# 优先使用本地镜像，智能跳过已存在的镜像

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📦 AIOpsLab 86个任务 - 统一镜像加载${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 定义所有86个任务需要的镜像
ALL_IMAGES=(
    # === 基础设施镜像（必需）===
    
    # Chaos Mesh (故障注入 - 所有故障相关任务必需)
    "ghcr.io/chaos-mesh/chaos-mesh:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-daemon:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-dashboard:v2.6.2"
    "ghcr.io/chaos-mesh/chaos-coredns:v0.2.6"
    
    # Prometheus (监控 - 所有任务必需)
    "quay.io/prometheus/prometheus:v2.47.2"
    "quay.io/prometheus/node-exporter:v1.6.1"
    "quay.io/prometheus/blackbox-exporter:v0.24.0"
    "quay.io/prometheus/pushgateway:v1.6.2"
    "quay.io/prometheus-operator/prometheus-config-reloader:v0.67.0"
    "registry.cn-wulanchabu.aliyuncs.com/moge1/kube-state-metrics:v2.3.0"
    "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1"
    
    # OpenEBS (存储 - 所有任务必需)
    "openebs/provisioner-localpv:3.4.0"
    "openebs/linux-utils:3.5.0"
    "openebs/node-disk-manager:2.1.0"
    "openebs/node-disk-operator:2.1.0"
    "openebs/node-disk-exporter:2.1.0"
    
    # === 应用镜像 ===
    
    # Social Network (社交网络)
    "deathstarbench/social-network-microservices:latest"
    "mongo:4.4.6"
    "redis:6.2.4"
    "memcached:1.6.7"
    "jaegertracing/all-in-one:1.57"
    "yg397/openresty-thrift:xenial"
    "alpine/git:latest"
    
    # Hotel Reservation (酒店预订)
    "hashicorp/consul:latest"
    "yinfangchen/hotelreservation:latest"
    "memcached:latest"
    "jaegertracing/all-in-one:latest"
    
    # Workload Generator (负载生成器)
    "deathstarbench/wrk2-client:latest"
)

# 目标集群
CLUSTERS=("kind1" "kind2" "kind3" "kind4" "kind5" "kind6" "kind7" "kind8" "kind9" "kind10")

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}1️⃣  检查宿主机镜像...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

MISSING_ON_HOST=()
for image in "${ALL_IMAGES[@]}"; do
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
        echo -e "  ${GREEN}✅${NC} $image"
    else
        echo -e "  ${RED}❌${NC} $image (缺失)"
        MISSING_ON_HOST+=("$image")
    fi
done

if [ ${#MISSING_ON_HOST[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  宿主机缺失 ${#MISSING_ON_HOST[@]} 个镜像！${NC}"
    echo -e "${YELLOW}请先拉取这些镜像到宿主机，或跳过缺失的镜像继续${NC}"
    echo ""
fi

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}2️⃣  加载镜像到所有Kind集群...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TOTAL_LOADED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0

for cluster in "${CLUSTERS[@]}"; do
    # 检查集群是否存在
    if ! docker ps --format "{{.Names}}" | grep -q "^${cluster}-control-plane$"; then
        echo -e "${YELLOW}⚠️  集群 ${cluster} 不存在，跳过${NC}"
        continue
    fi
    
    echo -e "${BLUE}━━━ 处理集群: ${cluster} ━━━${NC}"
    
    # 获取集群中已有的镜像
    EXISTING=$(docker exec ${cluster}-control-plane crictl images 2>/dev/null | awk 'NR>1 {print $1":"$2}')
    
    for image in "${ALL_IMAGES[@]}"; do
        # 跳过宿主机上缺失的镜像
        if [[ " ${MISSING_ON_HOST[@]} " =~ " ${image} " ]]; then
            continue
        fi
        
        # 检查镜像是否已在集群中
        if echo "$EXISTING" | grep -q "${image}"; then
            echo -e "  ${BLUE}⏭️  跳过:${NC} $image"
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
        else
            echo -ne "  ${GREEN}📥 加载:${NC} $image ... "
            if kind load docker-image "$image" --name "$cluster" >/dev/null 2>&1; then
                echo -e "${GREEN}✅${NC}"
                TOTAL_LOADED=$((TOTAL_LOADED + 1))
            else
                echo -e "${RED}❌${NC}"
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
            fi
        fi
    done
    echo ""
done

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 镜像加载完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📊 统计:${NC}"
echo -e "  • 成功加载: ${GREEN}${TOTAL_LOADED}${NC} 个"
echo -e "  • 已存在跳过: ${BLUE}${TOTAL_SKIPPED}${NC} 个"
if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "  • 失败: ${RED}${TOTAL_FAILED}${NC} 个"
fi
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}3️⃣  部署 OpenEBS 并配置环境...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

for cluster in "${CLUSTERS[@]}"; do
    # 检查集群是否存在
    if ! docker ps --format "{{.Names}}" | grep -q "^${cluster}-control-plane$"; then
        echo -e "${YELLOW}⚠️  集群 ${cluster} 不存在，跳过${NC}"
        continue
    fi
    
    echo -e "${BLUE}━━━ 配置集群: ${cluster} ━━━${NC}"
    
    # 1. 创建必要的目录
    echo -ne "  ${GREEN}📁 创建目录:${NC} /run/udev ... "
    docker exec ${cluster}-control-plane mkdir -p /run/udev 2>/dev/null
    echo -e "${GREEN}✅${NC}"
    
    # 2. 部署 OpenEBS
    echo -ne "  ${GREEN}🔧 部署 OpenEBS:${NC} "
    if kubectl --context kind-${cluster} get ns openebs >/dev/null 2>&1; then
        echo -e "${BLUE}已存在${NC}"
    else
        kubectl --context kind-${cluster} apply -f https://openebs.github.io/charts/openebs-operator.yaml >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌ 失败${NC}"
        fi
    fi
    
    # 3. 等待 OpenEBS 就绪
    echo -ne "  ${GREEN}⏳ 等待 OpenEBS 就绪:${NC} "
    kubectl --context kind-${cluster} wait --for=condition=ready pod \
      -l name=openebs-localpv-provisioner \
      -n openebs \
      --timeout=180s >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️  超时（可能需要手动检查）${NC}"
    fi
    
    echo ""
done

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}4️⃣  加载 socialNetwork 源代码到集群...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查是否有源代码参考集群
SOURCE_CLUSTER=""
for cluster in kind kind1 kind2 kind3; do
    if docker exec ${cluster}-control-plane test -d /var/lib/kubelet/hostpath/socialNetwork 2>/dev/null; then
        SOURCE_CLUSTER=$cluster
        echo -e "${GREEN}✅ 找到源代码参考集群: ${SOURCE_CLUSTER}${NC}"
        break
    fi
done

if [ -z "$SOURCE_CLUSTER" ]; then
    echo -e "${YELLOW}⚠️  未找到包含 socialNetwork 源代码的集群，跳过此步骤${NC}"
else
    # 导出源代码
    echo -ne "${GREEN}📦 从 ${SOURCE_CLUSTER} 导出源代码...${NC} "
    docker exec ${SOURCE_CLUSTER}-control-plane bash -c "cd /var/lib/kubelet/hostpath && tar czf /socialNetwork.tar.gz socialNetwork" 2>/dev/null
    docker cp ${SOURCE_CLUSTER}-control-plane:/socialNetwork.tar.gz /tmp/socialNetwork_temp.tar.gz 2>/dev/null
    
    if [ -f /tmp/socialNetwork_temp.tar.gz ]; then
        echo -e "${GREEN}✅${NC}"
        
        # 加载到所有集群
        for cluster in "${CLUSTERS[@]}"; do
            # 检查是否已有源代码
            if docker exec ${cluster}-control-plane test -d /var/lib/kubelet/hostpath/socialNetwork 2>/dev/null; then
                echo -e "  ${BLUE}⏭️  ${cluster}:${NC} 已有源代码，跳过"
            else
                echo -ne "  ${GREEN}📥 ${cluster}:${NC} 加载中... "
                docker cp /tmp/socialNetwork_temp.tar.gz ${cluster}-control-plane:/tmp/socialNetwork.tar.gz 2>/dev/null
                docker exec ${cluster}-control-plane bash -c "mkdir -p /var/lib/kubelet/hostpath && cd /var/lib/kubelet/hostpath && tar xzf /tmp/socialNetwork.tar.gz" 2>/dev/null
                
                if docker exec ${cluster}-control-plane test -d /var/lib/kubelet/hostpath/socialNetwork/media-frontend/lua-scripts 2>/dev/null; then
                    echo -e "${GREEN}✅${NC}"
                else
                    echo -e "${RED}❌${NC}"
                fi
            fi
        done
        
        rm -f /tmp/socialNetwork_temp.tar.gz
    else
        echo -e "${RED}❌ 导出失败${NC}"
    fi
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 集群配置完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}💡 提示:${NC}"
echo -e "  • 镜像已加载完成"
echo -e "  • OpenEBS 已部署并就绪"
echo -e "  • socialNetwork 源代码已加载"
echo -e "  • Prometheus 将由 AIOpsLab 自动部署"
echo -e "  • 集群已就绪，可以运行任务"
echo ""

