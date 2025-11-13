## Echo 持久化开发记录

### 1. 实现过程
- 在 `Echo/server.py` 中引入 `RESULTS_ROOT` 常量（可通过 `ECHO_RESULTS_DIR` 覆盖），并新增 `_persist_run_payload` 与 `_persist_job_results` 两个辅助函数。
- 在 `run_finished` 事件到来时调用 `_persist_run_payload`，将当前回合 payload 写入 `res/type1/<problem_id>/<job_id>/run_<index>.json`。
- 在 `job_finished` / `job_failed` 时调用 `_persist_job_results`，生成 `res/type2/<problem>/ <job_id>.json` 的汇总文件。
- 编写 `docs-cwy/persist_echo_results.md` 说明书，记录推荐做法、目录结构与注意事项。
- 通过 `start_rl_stack.py` + `curl /echo/jobs` 实际跑任务，确认 type1/type2 文件均按预期生成。

### 2. 核心评测指令（及原因）
1. **启动服务栈**
   ```bash
   /home/wanyi/anaconda3/envs/aoi/bin/python ./scripts/start_rl_stack.py \
     --problem-id container_kill-analysis-1 \
     --local-env-check
   ```
   使用 `aoi` 环境，避免缺失依赖；脚本会先启动 8099(`service_api`) 后启动 8098(Echo)，并执行 smoke 检查。

2. **提交测试任务**
   ```bash
   curl -X POST http://127.0.0.1:8099/echo/jobs \
     -H "Content-Type: application/json" \
     -d '{
           "problems": [
             {"problem_id": "container_kill-analysis-1", "runs": 2, "max_steps": 12}
           ],
           "concurrency": 1,
           "chat": {
             "model": "/data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail",
             "base_url": "http://14.103.221.215:18200/v1",
             "temperature": 0.2,
             "top_p": 1.0,
             "max_tokens": 512
           },
           "echo": {"url": "http://127.0.0.1:8098"}
         }'
   ```
   触发真实的 `run_finished` / `job_finished` 流程，校验落盘逻辑；仍然连导师提供的模型服务。

3. **查看运行状态与事件**
   ```bash
   curl http://127.0.0.1:8099/echo/jobs/<job_id>
   curl http://127.0.0.1:8098/jobs/<job_id>/events
   curl http://127.0.0.1:8099/echo/jobs/<job_id>/results
   ```
   确认状态从 `pending`→`running`→`finished`，并对比 `events/results` 与磁盘文件内容。

4. **验证落盘目录**
   ```bash
   find res -maxdepth 4 -type f
   ```
   检查 `type1`/`type2` 下是否生成对应 JSON；smoke 任务也会写到 `type2/smoke-problem/`。

5. **收尾**
   ```bash
   pkill -f "uvicorn service_api:app"
   pkill -f "uvicorn Echo.server:app"
   ```
   停止服务，释放 8099/8098 端口。

### 3. 8099 / 8098 / 模型服务的整体关系
- **8099 (`service_api`)**：FastAPI，负责 orchestrator 与模型交互，提供 `/rl/reset`、`/rl/step`、`/echo/jobs` 等接口。
- **8098 (Echo)**：接收训练任务事件并存储轨迹；新增的持久化逻辑就在这里生效。
- **模型服务**：外部 vLLM OpenAI 兼容接口（当前指向 `http://14.103.221.215:18200/v1`），`start_rl_stack.py` 不会启动模型，需要提前准备。
- 流程简述：`start_rl_stack.py` 启动 8099/8098 → `POST /echo/jobs` 创建任务 → `run_finished` 写 `res/type1` → `job_finished` 写 `res/type2` → 停止服务。

该文档用于团队复盘或后续维护，快速了解本次改动和验证方法。


### 4.cwy

1.模型机器（ssh -p 22200 root@14.103.221.215）

conda activate qwen_s

CUDA_VISIBLE_DEVICES=0 vllm serve /data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail --port 8080 --gpu-memory-utilization 0.4

2.service_api服务器 8099（aiopslab 需要用到kind集群）

cd /home/wanyi/projects/AI_SRE_Playground

python -m uvicorn service_api:app --host 0.0.0.0 --port 8099




3.Echo RL服务器 8098 （收数据、发任务）

cd /home/wanyi/projects/AI_SRE_Playground
conda activate /home/wanyi/anaconda3/envs/aoi
export PYTHONPATH=$(pwd)
export ECHO_RESULTS_DIR=/path/to/store/results   # 可选，自定义落盘目录

uvicorn Echo.server:app --host 0.0.0.0 --port 8098

curl -X POST http://<service机IP>:8099/echo/jobs \
  -H "Content-Type: application/json" \
  -d '{
        "problems": [
          {"problem_id": "container_kill-analysis-1", "runs": 2, "max_steps": 12}
        ],
        "concurrency": 1,
        "chat": {
          "model": "/data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail",
          "base_url": "http://<模型机IP>:8080/v1",
          "temperature": 0.2,
          "top_p": 1.0,
          "max_tokens": 512
        },
        "echo": {
          "url": "http://<Echo机IP>:8098"
        }
      }'


curl http://<service机IP>:8099/echo/jobs/<job_id>
curl http://<echo机IP>:8098/jobs/<job_id>/events
curl http://<service机IP>:8099/echo/jobs/<job_id>/results

--- 11.3更新
┌─────────────────────────────────────┐
│ 机器A（Service机）                   │
│ - 8099端口：service_api             │
│ - Kind集群：K8s环境                 │
│ - 作用：orchestrator + 环境管理    │
└─────────────────────────────────────┘
            ↓ HTTP请求
            ↓ 
┌─────────────────────────────────────┐
│ 机器B（模型+Echo机）                 │
│ - 8080端口：vLLM模型服务            │
│ - 8098端口：Echo服务器              │
│ - 作用：推理 + 数据收集             │
└─────────────────────────────────────┘
数据流向：
客户端 → 8099发起任务
8099 → 8098注册job
8099 ↔ 8080请求模型推理
8099 → 8098上报轨迹数据
客户端 ← 8099/8098查询结果


1.先测试 model + 8098 一台， 8099一台。 两台机器
14.103.221.215
步骤1：启动模型服务

conda activate qwen_s

CUDA_VISIBLE_DEVICES=0 vllm serve \
  /data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail \
  --port 8080 \
  --gpu-memory-utilization 0.4

步骤2:启动Echo服务
cd /root/projects/AI_SRE_Playground
conda activate aoi

# 启动Echo服务（端口8098）
uvicorn Echo.server:app --host 0.0.0.0 --port 8098

步骤3:Service机
106.14.183.16

conda activate aiopslab
cd /home/ecs-user/projects/AI_SRE_Playground-echo
export PYTHONPATH=/home/ecs-user/projects/AI_SRE_Playground-echo:$PYTHONPATH
python -m uvicorn service_api:app --host 0.0.0.0 --port 8099

步骤4:提交测试任务 模型机
cd /root/projects/AI_SRE_Playground
conda activate aoi
python send_job.py



补充单独评测：
cd /home/ecs-user/projects/AI_SRE_Playground-echo
conda activate aiopslab
export PYTHONPATH=/home/ecs-user/projects/AI_SRE_Playground-echo:$PYTHONPATH
python3 clients/gpt.py --problem k8s_target_port-misconfig-detection-1 --max-steps 5
---------
## 改动 10.31 - Echo 持久化功能实现

### 目标
将 Echo 服务接收到的训练数据自动保存到磁盘，方便后续分析。

### 改动方案

#### 1. 新增配置（文件开头）
- 添加 `logging` 和 `os` 导入
- 定义 `RESULTS_ROOT` 常量：默认 `项目根目录/res`，可通过环境变量 `ECHO_RESULTS_DIR` 自定义

#### 2. 新增两个持久化函数
**`_persist_run_payload(job, data)`**
- 触发时机：`run_finished` 事件
- 保存路径：`res/type1/<problem_id>/<job_id>/run_<index>.json`
- 内容：单次运行的完整 payload

**`_persist_job_results(job)`**
- 触发时机：`job_finished` 或 `job_failed` 事件
- 保存路径：`res/type2/<problem_id>/<job_id>.json`
- 内容：整个 job 的汇总结果（所有 runs）

#### 3. 修改 `_handle_job_event` 函数
在三个事件处理分支添加持久化调用：
- `run_finished` → 调用 `_persist_run_payload`
- `job_finished` → 调用 `_persist_job_results`
- `job_failed` → 调用 `_persist_job_results`

#### 4. JobRecord 新增方法
添加 `as_results_payload()` 方法，生成包含所有 runs 的完整结果字典

### 目录结构示例
```
res/
├── type1/          # 单次运行详情
│   └── container_kill-analysis-1/
│       └── abc123/
│           ├── run_0.json
│           └── run_1.json
└── type2/          # Job 汇总结果
    └── container_kill-analysis-1/
        └── abc123.json
```

### 验证方法
1. 启动 Echo 服务（8098）
2. 提交测试任务
3. 检查 `res/type1` 和 `res/type2` 目录是否生成文件
4. 验证 JSON 内容完整性

---------

待优化：

## 🎯 Reward 机制优化

### 当前问题
**核心配置**：`aiopslab/orchestrator/rl_env.py:59-64`
```python
success: float = 1.0              # 提交成功就给 1.0 分
invalid_submission: float = -1.0  # 格式错误扣 1.0 分
step: float = -0.01               # 每步扣 0.01
timeout: float = -0.5             # 超时扣 0.5
command_match_multiplier: 0.1     # 执行专家命令加成
```

**致命缺陷**：
1. **答案正确与否不影响 reward**
   - 当前：`VALID_SUBMISSION` → `reward = 1.0`（不管答案对错）
   - 结果：模型学会"直接猜答案"（你的数据显示 5 步就提交，reward=0.96 但 success=False）
   
2. **Step Penalty 太小**
   - 调查 30 步 vs 直接猜 5 步：差值仅 -0.25 分
   - 没有动力去真正分析问题

3. **逻辑时序问题**
   - `_compute_rewards()` 在 `step()` 中立即执行
   - `eval()` 评估在 `_finalize_session()` 中执行
   - 导致无法在 reward 中使用 `success/system_level_correct/fault_type_correct`

### 优化方案

#### 方案 A：延迟 Reward 计算（推荐）
```python
def _compute_rewards(self, parsed, env_response):
    if env_response == SubmissionStatus.VALID_SUBMISSION:
        # 第一步：先给基础奖励（提交格式正确）
        base_reward = 0.3
        
        # 第二步：在 _finalize_session 后补充正确性奖励
        # 需要改造为支持"延迟 reward 返回"
        # 或者在 trajectory 中记录 "pending_reward"，训练时再合并
        
        return base_reward, True, False
```

#### 方案 B：调整 Reward 权重
```python
# 即使无法使用正确性，也可以通过权重引导行为
success: float = 0.5           # 降低提交奖励
step: float = -0.02            # 增加 step 惩罚（鼓励效率）
command_match_multiplier: 0.3  # 增加专家命令奖励（鼓励调查）
```

#### 方案 C：分步奖励
```python
# 给每个有用的中间动作小奖励
if api_name in ["get_logs", "get_metrics", "exec_shell"]:
    reward += 0.05  # 鼓励收集信息
    
# 对重复无效动作惩罚
if is_duplicate_action(action, history):
    reward -= 0.02
```

---

## 🔄 容错机制：Echo 事件重传

### 当前问题
**位置**：`service_api.py:525-533` `_post_echo_event()`

```python
async def _post_echo_event(job, payload):
    try:
        await job.echo_client.post_event(job.echo_job_id, payload)
    except Exception as exc:
        logger.exception("Failed to post event")  # ❌ 只记录日志，数据丢失！
        return str(exc)
```

**问题场景**：
- 网络抖动 → 单次失败 → 训练数据永久丢失
- Echo (8098) 重启 → 所有 in-flight 事件丢失
- 只统计 `echo_failures` 计数，无恢复机制

### 优化方案

#### 阶段 1：指数退避重试（立即实施）
```python
@dataclass
class RetryConfig:
    max_retries: int = 3
    initial_delay: float = 1.0
    max_delay: float = 30.0
    exponential_base: float = 2.0

async def _post_echo_event_with_retry(job, payload, retry_config):
    """
    网络临时故障自动重试
    """
    for attempt in range(retry_config.max_retries + 1):
        try:
            await job.echo_client.post_event(job.echo_job_id, payload)
            return None  # 成功
        except httpx.TimeoutException:
            if attempt >= retry_config.max_retries:
                break
            delay = min(
                retry_config.initial_delay * (retry_config.exponential_base ** attempt),
                retry_config.max_delay
            )
            await asyncio.sleep(delay)
        except httpx.HTTPStatusError as exc:
            # 4xx 错误不重试，5xx 错误重试
            if exc.response.status_code < 500:
                return str(exc)
    return f"Failed after {retry_config.max_retries + 1} attempts"
```

**优点**：
- ✅ 改动小（~50 行代码）
- ✅ 解决 90% 的网络抖动问题
- ✅ 可配置策略

#### 阶段 2：本地缓冲 + 后台重发（高可用）
```python
class EchoEventBuffer:
    """
    失败事件缓冲到内存，后台异步重试
    """
    def __init__(self, max_size: int = 10000):
        self._buffer: deque[PendingEvent] = deque(maxlen=max_size)
        
    async def add(self, event: PendingEvent):
        """失败时加入缓冲"""
        self._buffer.append(event)
        
    async def start_retry_loop(self, interval: float = 10.0):
        """后台任务：每 10 秒重试一次缓冲区"""
        while True:
            await asyncio.sleep(interval)
            await self._retry_all()
```

**优点**：
- ✅ Echo 重启不丢数据
- ✅ 长时间断连可恢复
- ⚠️ 需要考虑内存占用（可配置 max_size）

#### 阶段 3：持久化缓冲（生产级）
```python
# 使用 SQLite 或 Redis 持久化失败事件
class PersistentEventBuffer:
    def __init__(self, db_path: str = "echo_buffer.db"):
        self.conn = sqlite3.connect(db_path)
        self._create_tables()
    
    def add(self, event: PendingEvent):
        """写入数据库，service_api 重启不丢失"""
        self.conn.execute(
            "INSERT INTO pending_events VALUES (?, ?, ?)",
            (event.job_id, event.payload, event.attempts)
        )
```

---

## 🚀 并发优化：支持多 service_api 实例

### 当前架构限制
- 单个 service_api (8099) 处理所有任务
- `concurrency` 参数只控制单机并发（默认 1）
- 无法水平扩展

### 优化方案

#### 选项 A：客户端负载均衡（最简单）
```python
# send_job.py
SERVICE_INSTANCES = [
    "http://106.14.183.16:8099",
    "http://另一台机器:8100",
    "http://另一台机器:8101",
]

def select_service(problem_id: str) -> str:
    """根据 problem_id 哈希选择实例"""
    import hashlib
    idx = int(hashlib.md5(problem_id.encode()).hexdigest(), 16) % len(SERVICE_INSTANCES)
    return SERVICE_INSTANCES[idx]

# 使用
service_url = select_service("container_kill-analysis-1")
resp = requests.post(f"{service_url}/echo/jobs", json=payload)
```

**优点**：
- ✅ 零依赖，改动极小
- ✅ 同一 problem_id 总是路由到同一实例（方便调试）

**缺点**：
- ⚠️ 负载不均衡（某个实例可能过载）
- ⚠️ 实例故障需要手动剔除

#### 选项 B：Nginx 负载均衡（推荐）
```nginx
upstream service_api_cluster {
    least_conn;  # 最少连接数算法
    server 106.14.183.16:8099 max_fails=3 fail_timeout=30s;
    server another-ip:8100 max_fails=3 fail_timeout=30s;
    server another-ip:8101 max_fails=3 fail_timeout=30s;
}

server {
    listen 9000;
    location /echo/jobs {
        proxy_pass http://service_api_cluster;
        proxy_next_upstream error timeout http_500 http_502 http_503;
    }
}
```

**客户端改动**：
```python
# 只需改 URL
resp = requests.post("http://nginx-ip:9000/echo/jobs", json=payload)
```

**优点**：
- ✅ 自动故障转移
- ✅ 负载均衡算法成熟（least_conn/ip_hash）
- ✅ 健康检查

#### 选项 C：任务队列（生产级）
```
          Client
             ↓
      POST /echo/jobs
             ↓
      service_api-1  ──┐
                       ├──→ Redis Queue
      service_api-2  ──┘     │
             ↑               │
             └───── Worker ──┘
```

**改造**：
```python
# service_api.py
@app.post("/echo/jobs")
async def start_training_job(payload: BatchRunRequest):
    """加入队列，立即返回"""
    job_id = uuid4().hex
    await redis_client.lpush("echo_jobs", json.dumps({
        "job_id": job_id,
        "payload": payload.model_dump()
    }))
    return {"job_id": job_id, "status": "queued"}

# 新增：worker.py
async def worker_loop():
    """每个实例启动 N 个 worker 消费任务"""
    while True:
        job_data = await redis_client.brpop("echo_jobs", timeout=5)
        if job_data:
            await _run_training_job(job_data)
```

**优点**：
- ✅ 完全解耦，易扩展
- ✅ 任务持久化（Redis AOF）
- ✅ 支持优先级队列

**缺点**：
- ⚠️ 引入 Redis 依赖
- ⚠️ 架构复杂度增加

---

## 📋 实施建议

### 优先级排序

| 优化项 | 优先级 | 实施难度 | 预期收益 |
|--------|--------|----------|----------|
| Echo 重试机制 | 🔥 P0 | 低（~50 行） | 解决 90% 数据丢失 |
| Nginx 负载均衡 | ⭐ P1 | 低（配置） | 支持 2-3 倍扩展 |
| Reward 权重调整 | ⭐ P1 | 低（改配置） | 提升训练质量 |
| 事件缓冲机制 | 📌 P2 | 中（~200 行） | 高可用保障 |
| 任务队列 | 📌 P2 | 高（架构改造） | 支持 10+ 倍扩展 |
| Reward 延迟计算 | 💡 P3 | 高（需改 RL 流程） | 理论最优，但工程量大 |

### 快速验证路径
```bash
# 1. 先实施 Echo 重试（明天就能上线）
git checkout -b feat/echo-retry
# 修改 service_api.py 添加重试逻辑
pytest tests/test_service_api.py
git commit -m "feat: add echo event retry with exponential backoff"

# 2. 部署多个 service_api + Nginx（下周）
# 在另一台机器启动 service_api:8100
uvicorn service_api:app --host 0.0.0.0 --port 8100

# 配置 Nginx 负载均衡
nginx -s reload

# 3. 调整 Reward 权重做 A/B 测试（并行）
# 对比不同配置的训练效果
```

---

## 📝 相关代码位置

| 功能 | 文件路径 | 关键行号 |
|------|----------|----------|
| Reward 配置 | `aiopslab/orchestrator/rl_env.py` | 43-64 |
| Reward 计算 | `aiopslab/orchestrator/rl_env.py` | 472-496 |
| Echo 事件发送 | `service_api.py` | 525-533 |
| Echo 客户端 | `service_api.py` | 400-455 |
| 任务执行主流程 | `service_api.py` | 536-577 |
| Echo 事件持久化 | `Echo/server.py` | 266-309 |
