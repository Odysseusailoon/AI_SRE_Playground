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

/home/wanyi/anaconda3/envs/aoi/bin/python -m uvicorn service_api:app --host 0.0.0.0 --port 8099




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


