#!/bin/bash

# =============================================================================
# 监控 kind11 集群的 Pod 状态
# =============================================================================

POD_LOG="${1:-cwy/log/test/task_kind-test_pods_stages.txt}"
CLUSTER="kind-test"
INTERVAL=60  # 每60秒记录一次

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$POD_LOG"
echo "Kind-test Pod 状态监控" >> "$POD_LOG"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$POD_LOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$POD_LOG"
echo "" >> "$POD_LOG"

STAGE=1

while true; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$POD_LOG"
    echo "阶段 $STAGE - $(date '+%Y-%m-%d %H:%M:%S')" >> "$POD_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$POD_LOG"
    echo "" >> "$POD_LOG"
    
    # 获取所有命名空间的 pod
    echo "【所有命名空间 Pod 概览】" >> "$POD_LOG"
    kubectl --context "kind-${CLUSTER}" get pods --all-namespaces -o wide 2>&1 >> "$POD_LOG"
    echo "" >> "$POD_LOG"
    
    # 检查是否有 test-social-network 命名空间
    if kubectl --context "kind-${CLUSTER}" get namespace test-social-network >/dev/null 2>&1; then
        echo "【test-social-network 命名空间详细状态】" >> "$POD_LOG"
        kubectl --context "kind-${CLUSTER}" get pods -n test-social-network -o wide 2>&1 >> "$POD_LOG"
        echo "" >> "$POD_LOG"
        
        # 统计 Pod 状态
        echo "【Pod 状态统计】" >> "$POD_LOG"
        kubectl --context "kind-${CLUSTER}" get pods -n test-social-network --no-headers 2>/dev/null | \
            awk '{print $3}' | sort | uniq -c >> "$POD_LOG"
        echo "" >> "$POD_LOG"
    fi
    
    # 检查是否有其他测试命名空间
    for ns in $(kubectl --context "kind-${CLUSTER}" get namespaces --no-headers 2>/dev/null | grep "test-" | awk '{print $1}'); do
        if [ "$ns" != "test-social-network" ]; then
            echo "【${ns} 命名空间】" >> "$POD_LOG"
            kubectl --context "kind-${CLUSTER}" get pods -n "$ns" -o wide 2>&1 >> "$POD_LOG"
            echo "" >> "$POD_LOG"
        fi
    done
    
    echo "" >> "$POD_LOG"
    
    STAGE=$((STAGE + 1))
    sleep $INTERVAL
done

