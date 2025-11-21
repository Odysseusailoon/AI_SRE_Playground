# 11.20
找到根源了！ 这些 SYN-SENT 连接都是卡住的连接尝试：
kube-apiserver → etcd (2379端口)：连接卡住
kubelet → kube-apiserver (6443端口)：连接卡住
kubelet → etcd (2381端口)：连接卡住
kubelet → node-exporter (9100端口)：连接卡住

## 11.19
测试一个kind 11指令
cd /home/ecs-user/projects/AI_SRE_Playground-echo
nohup bash run_kind11_test.sh > logs/test/kind11_wrapper.log 2>&1 &


检查pod指令
kubectl --context kind-kind11 get pods -n openebs
kubectl --context kind-kind11 get pods -n test-social-network
kubectl --context kind-kind11 get pods -n test-hotel-reservation

Pod创建流程：
1. kubectl创建Pod → API Server
2. API Server存储到etcd
3. 调度器(scheduler)从API Server读取待调度Pod
4. 调度器选择节点 → 写回API Server
5. kubelet在节点上启动Pod

当前问题：第3步失败！
调度器崩溃 → 无法读取待调度Pod → 所有Pod永远Pending
kube-scheduler-kind1-control-plane 状态是 CrashLoopBackOff


✅ CPU: 12%使用，82%空闲
✅ 内存: 266GB可用
✅ 磁盘IO: 0.1%等待
❌ 网络连接：枯竭（400万僵尸连接）
为什么是etcd？

etcd特点：
- 每次读写都是独立的TCP连接
- 频繁的短连接（不像长连接可复用）
- 对延迟非常敏感

当网络资源紧张时：
1. 新TCP连接建立变慢（SYN队列满）
2. etcd请求超时（默认5秒）
3. 返回错误：connection timed out 

连锁反应：
etcd超时 → API Server超时 → 调度器超时 → 调度器崩溃
Kind容器内没有明确的"连接总数"硬上限，但有实际瓶颈：
端口数上限：28,232个（主动连接）
性能瓶颈：38,000+僵尸连接导致
内存消耗
端口查找变慢
新连接建立超时
当前kind1状态：38,349个CLOSED连接远超合理范围（正常应该<100），导致etcd新连接超时失败。

tw_sock_TCP 使用率 99.6%！
tw_sock_TCP slab 缓存:  active: 16,063  total:  16,120  free:   57      ← 只剩 57 个空位！  usage:  99.6%   ← 接近满载！
这就是性能拐点！

=== 停止前：kind1 的 tw_sock_TCP 状态 ===
TCP 统计:
TCP: inuse 224 orphan 1510 tw 52 alloc 41354 mem 49682

Slab 缓存详情:
tw_sock_TCPv6         active:  15314  total:  15562  usage: 98.4%
tw_sock_TCP           active:  16955  total:  17298  usage: 98.0%

## 11.18

# start command (单实例)
cd /home/ecs-user/projects/AI_SRE_Playground-echo
source ~/miniconda3/bin/activate aiopslab
export PYTHONPATH=$(pwd):$PYTHONPATH
nohup python -u clients/gpt.py --problem k8s_target_port-misconfig-mitigation-1 --max-steps 30 > logs/gpt_eval.log 2>&1 &

并行
cd /home/ecs-user/projects/AI_SRE_Playground-echo && \
rm -f logs/parallel/task_*.log logs/parallel/wrapper_*.sh && \
nohup bash parallel_test_4_different_tasks.sh > logs/parallel_test_10.log 2>&1 & \
echo "✓ 并行测试已启动，PID: $!" && \
echo "✓ 查看日志: tail -f logs/parallel_test_10.log"
# 查看

kill：
pkill -f 'python3.*gpt.py'
# 查看系统资源
echo "=== 系统资源概览 ===" && echo "CPU: $(nproc)核 | 负载:$(uptime | awk -F'load average:' '{print $2}')" && free -h | awk 'NR==2{printf "内存: %s / %s (已用 %s)\n", $3, $2, $3}' && df -h / | awk 'NR==2{printf "磁盘: %s / %s (%s)\n", $3, $2, $5}' && echo "任务: $(ps aux | grep "python3.*gpt.py" | grep -v grep | wc -l)/10 运行中"

查看景象
docker images 
看全部 Pod 状态（含 IP/节点）
kubectl get pods -n test-social-network -o wide


# 查看集群
kind get clusters

# openebs -- observe -- test-social-network

kubectl --context kind-kind get pods -n openebs
kubectl --context kind-kind11 get pods -n openebs
kubectl --context kind-kind2 get pods -n openebs

kubectl --context kind-kind get pods -n observe
kubectl --context kind-kind1 get pods -n observe
kubectl --context kind-kind2 get pods -n observe

kubectl --context kind-kind get pods -n test-social-network
kubectl --context kind-kind1 get pods -n test-social-network
kubectl --context kind-kind2 get pods -n test-social-network

# back
# Kubernetes control node
k8s_host: kind
# kind cluster name (only used when k8s_host is "kind" and kube_context is not set)
kind_cluster_name: kind

# Explicit kube_context for kind1 cluster (uncomment to use kind2: kind-kind2)
# kube_context: kind-kind

k8s_user: ecs-user

# ssh key path
ssh_key_path: ~/.ssh/id_rsa

# Directory where data files are stored
data_dir: data

# Flag to enable/disable qualitative evaluation (makes LLM calls)
qualitative_eval: false

# Flag to enable/disable supervisor evaluation for detection tasks (makes LLM calls)
supervisor_eval: false

# Flag to enable/disable printing the session
print_session: false



# 具体问题

kube-proxy 错误: "command failed" err="failed complete: too many open files"

OpenEBS 无法连接到 Kubernetes API Server
kube-proxy 崩溃了，因为它试图打开太多文件
没有 kube-proxy，就没有网络转发
没有网络转发，就无法连接 10.96.0.1 （API Server）
无法连接 API Server，所有组件都会崩溃


1. 宿主机上的压缩包：
/tmp/socialNetwork.tar.gz (23MB)
2. kind1 容器内的解压目录：
/var/lib/kubelet/hostpath/socialNetwork/
3. 关键的 lua-scripts 路径（容器内）：
/var/lib/kubelet/hostpath/socialNetwork/media-frontend/lua-scripts/  ├── get-media.lua  └── upload-media.lua

---

## 🔍 深度调查：连接产生根源（2025-11-20 10:30）

### 根本原因

**87 个 Kind 集群全部运行** → 即使不执行任务也在持续产生连接：

```
宿主机总连接：26,745 个
├─ 87 个 Kind 集群 × 平均 200-300 连接/集群 = ~17,400-26,100 个内部连接
└─ 每个集群的 K8s 组件都在运行健康检查、探活、监控采集
```

**连接产生速率**：
- 健康检查：kubelet → kube-apiserver, kube-apiserver → etcd (10 秒/次)
- Pod 探活：kubelet → 每个 Pod (3-10 秒/次)  
- Prometheus 采集：Prometheus → node-exporter, Pod metrics (15 秒/次)
- **估算：87 集群 × 10 组件 × 6 次/分钟 = 每分钟 5,220 次连接！**

### 恶性循环的完整机制

```
【根源】87 个 Kind 集群持续运行
    ↓
【表象 1】大量短连接产生（5,220 次/分钟）
    ↓
【表象 2】连接关闭后进入 TIME-WAIT 状态（持续 15-60 秒）
    ↓
【瓶颈 1】tw_sock 缓存饱和（98-99% 使用率）
    ↓
【瓶颈 2】新建 socket 变慢（从 0.01 秒 → 5-10 秒）
    ↓
【故障 1】etcd/kube-apiserver 连接超时（5 秒阈值）
    ↓
【故障 2】组件不断重试 → kube-apiserver 堆积 66 个到 etcd 的连接
    ↓
【故障 3】etcd 被拖垮（响应时间 0.01秒 → 2分12秒）
    ↓
【故障 4】K8s 组件崩溃重启（CrashLoopBackOff）
    ↓
【恶化】组件重启产生更多连接 → 循环加剧 ❌
```

### 重启 kube-apiserver 的效果

**立即效果（T+0）**：✅ 临时有效
- kube-apiserver → etcd 连接：66 → 4
- etcd 总连接：150 → 18
- etcd 响应时间：2分12秒 → 0.073秒

**30 秒后（T+30）**：❌ 快速重现
- kube-apiserver → etcd 连接：4 → 61
- etcd 总连接：18 → 132  
- tw_sock 使用率：回到 98.8%

**结论**：重启只是短暂缓解，87 个集群的持续运行会在 30-60 秒内重现问题。

### 关于 "closed" 连接

**❌ 不存在手动清空的方法**：

1. **TIME-WAIT 状态**：
   - TCP 协议规定的必经状态
   - 持续时间：15-60 秒（由 `tcp_fin_timeout` 控制）
   - 目的：防止旧连接的延迟数据包干扰新连接
   - **无法手动清空**，只能等内核自动回收

2. **SYN-SENT 状态**：
   - 正在尝试建立但对方未响应的连接
   - 超时时间：通常 20-120 秒
   - 超时后会自动关闭

3. **ESTAB 状态**：
   - 正常的已建立连接
   - 只有进程主动关闭或连接断开才会释放

**为什么不能手动清空 tw_sock 缓存？**
- Slab 缓存是内核自动管理的，没有清空命令
- 强制删除会导致：
  - TCP 协议栈状态混乱
  - 端口冲突（新连接可能复用旧端口）
  - 数据包错乱（旧连接的延迟包干扰新连接）
  
**唯一有效方法**：减少新连接产生速度，让回收速度 > 产生速度

### 解决方案

**方案 1：停止不使用的 Kind 集群** ⭐ **推荐**

```bash
# 停止除 kind1 之外的所有集群
for i in kind{2..86}; do docker stop ${i}-control-plane; done

# 或者全部停止，按需启动
docker stop $(docker ps -q --filter "name=kind.*-control-plane")
```

**方案 2：调整内核参数（已测试有效）**

```bash
# 对所有运行中的集群应用
for i in $(docker ps --format "{{.Names}}" | grep "kind.*-control-plane"); do
  docker exec $i sysctl -w net.ipv4.tcp_fin_timeout=15
  docker exec $i sysctl -w net.ipv4.tcp_tw_reuse=1
done
```

**方案 3：资源隔离**
- 87 个集群分批测试，每批不超过 4-5 个
- 或者使用更强大的宿主机（更多 CPU 核心，更快的 IO）