# start command (单实例)
cd /home/ecs-user/projects/AI_SRE_Playground-echo
conda activate aiopslab
export PYTHONPATH=/home/ecs-user/projects/AI_SRE_Playground-echo:${PYTHONPATH}
nohup python3 /home/ecs-user/projects/AI_SRE_Playground-echo/clients/gpt.py \
  --problem k8s_target_port-misconfig-detection-1 \
  --max-steps 5 \
  > /home/ecs-user/projects/AI_SRE_Playground-echo/logs/gpt_eval.log 2>&1 & echo $! > /home/ecs-user/projects/AI_SRE_Playground-echo/logs/gpt_eval.pid




查看景象
docker images 
看全部 Pod 状态（含 IP/节点）
kubectl get pods -n test-social-network -o wide


# 查看集群
kind get clusters

# openebs -- observe -- test-social-network

kubectl --context kind-kind get pods -n openebs
kubectl --context kind-kind1 get pods -n openebs
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