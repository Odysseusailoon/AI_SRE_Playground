#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🔍 检测所有集群环境${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CLUSTERS=("kind" "kind1" "kind2" "kind3")
ALL_OK=true

for cluster in "${CLUSTERS[@]}"; do
    echo -e "${YELLOW}━━━ 检查集群: ${cluster} ━━━${NC}"
    
    # 检查集群是否运行
    if ! docker ps --format "{{.Names}}" | grep -q "^${cluster}-control-plane$"; then
        echo -e "  ${RED}❌ 集群不存在${NC}"
        ALL_OK=false
        continue
    fi
    
    # 检查节点状态
    NODE_STATUS=$(kubectl --context kind-${cluster} get nodes --no-headers 2>/dev/null | awk '{print $2}')
    if [ "$NODE_STATUS" = "Ready" ]; then
        echo -e "  ${GREEN}✅ 节点状态: Ready${NC}"
    else
        echo -e "  ${RED}❌ 节点状态: $NODE_STATUS${NC}"
        ALL_OK=false
    fi
    
    # 检查关键namespace
    NAMESPACES=$(kubectl --context kind-${cluster} get ns --no-headers 2>/dev/null | awk '{print $1}')
    
    # 检查openebs
    if echo "$NAMESPACES" | grep -q "openebs"; then
        OPENEBS_PODS=$(kubectl --context kind-${cluster} get pods -n openebs --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        if [ "$OPENEBS_PODS" -eq 0 ]; then
            echo -e "  ${GREEN}✅ OpenEBS: OK${NC}"
        else
            echo -e "  ${YELLOW}⚠️  OpenEBS: $OPENEBS_PODS pods not ready${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  OpenEBS: 未安装${NC}"
    fi
    
    # 检查chaos-mesh
    if echo "$NAMESPACES" | grep -q "chaos-mesh"; then
        CHAOS_PODS=$(kubectl --context kind-${cluster} get pods -n chaos-mesh --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        if [ "$CHAOS_PODS" -eq 0 ]; then
            echo -e "  ${GREEN}✅ Chaos Mesh: OK${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Chaos Mesh: $CHAOS_PODS pods not ready${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  Chaos Mesh: 未安装${NC}"
    fi
    
    # 检查observe (Prometheus)
    if echo "$NAMESPACES" | grep -q "observe"; then
        OBSERVE_PODS=$(kubectl --context kind-${cluster} get pods -n observe --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        if [ "$OBSERVE_PODS" -eq 0 ]; then
            echo -e "  ${GREEN}✅ Prometheus: OK${NC}"
        else
            echo -e "  ${YELLOW}⚠️  Prometheus: $OBSERVE_PODS pods not ready${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  Prometheus: 未安装${NC}"
    fi
    
    echo ""
done

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✅ 所有集群环境检查通过！${NC}"
else
    echo -e "${YELLOW}⚠️  部分集群有警告，但可以继续测试${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

