# Task Executor

RESTful API for scalable AIOpsLab task execution with integrated worker management.

## 当前理解、目标与现状

### 我们对 Task Executor 的理解
- 提供 FastAPI 驱动的任务执行服务，将外部提交的 AIOpsLab 问题排队、调度并记录执行全流程。
- 通过数据库驱动的任务队列 (`SELECT FOR UPDATE SKIP LOCKED`) 与 REST 接口连接外部调用方与内部/外部 worker。
- 在同一进程内托管 `WorkerManager`，自动拉起内部 worker 并可选调用真实的 AIOpsLab Orchestrator。

### 当前目标
- 暴露稳定的任务生命周期 API（创建、查询、取消、日志、统计），供上层在线 RL / Agent 组件复用。
- 保证 worker 与任务之间的绑定与调度策略满足规格中“一对一 backend 映射、Kind 隔离”的要求。
- 维持可观测性：Prometheus `/metrics`、结构化日志、LLM 会话留存。
- 为后续扩展（多后端 worker、真实 orchestrator、LLM 回话可视化）打好数据模型和服务接口基础。

### 系统现状（2025-09-17）
- ✅ API、任务队列、数据模型、内部 worker 框架均已实现并可启动。
- ⚠️ 已知技术债：
  - `/metrics` 端点使用 `async with get_db()` 会抛错，Prometheus 当前不可用。
  - Worker 完成/失败接口缺乏任务归属校验，存在越权风险。
  - `LLMLoggingAgent` 对异步 Agent 处理不当，执行真实 orchestrator 时会抛 `TypeError`。
  - `OrchestratorExecutor` 在事件循环内执行阻塞操作（Kind 管理、`orchestrator.run()`），可能卡死整个 API。
  - 任务分配暂未依据 worker backend/capabilities 过滤，无法满足规格中的能力约束。
- 🛠️ 下一步会优先修复上述高优先级问题，并补充测试/文档。

## Architecture

```
task-executor/
├── api/                    # RESTful API Server with integrated workers
│   ├── src/               # Source code
│   │   ├── api/          # API endpoints
│   │   ├── models/       # Database models
│   │   ├── services/     # Business logic
│   │   ├── schemas/      # Pydantic schemas
│   │   ├── lib/          # Libraries (task queue)
│   │   └── workers/      # Internal worker management
│   ├── tests/            # Test suites
│   └── pyproject.toml    # Python dependencies (Poetry)
```

## Key Changes from Previous Version

✨ **Workers are now integrated into the API process** - No need to manually start separate worker processes. The API automatically manages internal workers as background tasks.

## Components

### API Server with Integrated Workers
- **Framework**: FastAPI with async support
- **Database**: PostgreSQL with SQLAlchemy ORM
- **Task Queue**: Database-backed queue using SELECT FOR UPDATE SKIP LOCKED
- **Workers**: Internal background tasks managed by the API
- **Monitoring**: Prometheus metrics and structured logging

## Key Features

- **Integrated Workers**: Workers run as background tasks within the API process
- **Auto-scaling**: Dynamic worker scaling via API endpoints
- **Atomic Task Claiming**: SELECT FOR UPDATE SKIP LOCKED prevents race conditions
- **Comprehensive Monitoring**: Metrics, logs, and real-time status
- **Flexible Configuration**: Environment variables for all settings
- **Automatic Recovery**: Timeout handling and error recovery
- **Real Orchestrator Integration**: Workers can调度真实 AIOpsLab Orchestrator，自动管理 Kind 集群并记录 LLM 会话

## Quick Start

```bash
# 1. Start PostgreSQL
docker-compose up -d

# 2. Install dependencies
cd api
poetry install

# 3. Start API (workers start automatically!)
poetry run uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

That's it! The API will automatically start 3 internal workers by default.

### 数据初始化 / 清理

要保证导出的轨迹全部来源于真实运行，可在 PostgreSQL 中清空现有记录：

```bash
docker exec -i aiopslab_postgres psql -U aiopslab -d aiopslab <<'SQL'
TRUNCATE TABLE llm_conversations CASCADE;
TRUNCATE TABLE task_logs CASCADE;
TRUNCATE TABLE tasks CASCADE;
TRUNCATE TABLE workers CASCADE;
SQL
```

（注意：这会删除所有历史数据，请在执行前确认已备份。）

## Configuration

Create a `.env` file in the `api` directory:

```bash
# Database
DATABASE_URL=postgresql+asyncpg://aiopslab:aiopslab@localhost:5432/aiopslab

# Worker Settings
NUM_INTERNAL_WORKERS=3      # Number of workers to start
AUTO_START_WORKERS=true      # Auto-start workers on API startup

# Task Settings
DEFAULT_TIMEOUT_MINUTES=30   # Task timeout
DEFAULT_MAX_STEPS=30         # Max steps for task execution
```

## API Endpoints

### Tasks
- `POST /api/v1/tasks` - Create new task
- `GET /api/v1/tasks` - List tasks with filtering
- `GET /api/v1/tasks/{id}` - Get task details
- `PUT /api/v1/tasks/{id}/cancel` - Cancel task
- `GET /api/v1/tasks/{id}/logs` - Get task logs
- `GET /api/v1/tasks/stats` - Queue statistics

### Workers
- `GET /api/v1/workers` - List all workers
- `GET /api/v1/workers/{id}` - Get worker details
- `GET /api/v1/workers/{id}/stats` - Worker statistics

### Internal Worker Control
- `GET /api/v1/workers/internal/status` - Internal worker status
- `POST /api/v1/workers/internal/scale?num_workers=N` - Scale workers
- `POST /api/v1/workers/internal/stop` - Stop all workers
- `POST /api/v1/workers/internal/start` - Start workers

### Monitoring
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics

## 数据导出

提供脚本 `scripts/export_task_data.py` 用于通过 REST API 批量导出任务、日志和 LLM 会话：

```bash
# 导出到 tmp/export.json，默认包含任务日志和会话
scripts/export_task_data.py http://localhost:8000 --output tmp/export.json

# 仅导出最近 100 条任务，不包含会话
scripts/export_task_data.py http://localhost:8000 --max-tasks 100 --skip-conversations
```

脚本默认使用 Python 3.11，可通过 `--page-size`、`--max-tasks` 等参数控制分页，输出文件为结构化 JSON，便于后续 RL 数据管线消费。如命令提示缺少依赖，可运行 `pip install requests` 安装所需库。

### 运行真实 Orchestrator

要启用真实 orchestrator 执行，需要：

1. 安装并配置 `kind`、`kubectl`（确保 Docker/k8s 环境可用）；
2. 在 `.env` 中提供 LLM 凭证（如 `OPENAI_API_KEY` 或 `OPENROUTER_API_KEY`）；
3. 保持 `AUTO_START_WORKERS=true`、`ENABLE_BACKGROUND_TASKS=true`（默认），启动 API：

   ```bash
   AUTO_START_WORKERS=true ENABLE_BACKGROUND_TASKS=true \
   DATABASE_URL=postgresql+asyncpg://aiopslab:aiopslab@localhost:5432/aiopslab \
   uvicorn src.main:app --host 0.0.0.0 --port 8000
   ```

4. 提交任务时指定期望后端（默认 `internal`，如需专门 orchestrator worker 可设置为 `orchestrator`）：

   ```bash
   curl -X POST http://localhost:8000/api/v1/tasks \
     -H "Content-Type: application/json" \
     -d '{
           "problem_id": "misconfig_app_hotel_res-detection-1",
           "parameters": {
             "backend_type": "internal",
             "agent_config": {"model": "gpt-4o"}
           }
         }'
   ```

注册自定义 worker 时，可将 `backend_type` 设置为 `orchestrator` 并在 `capabilities.supported_problems` 中列出可处理的问题；队列仅会分发匹配后端的任务。

## Testing the System

Run the integrated test script:

```bash
cd task-executor
python test_integrated.py
```

This will:
1. Check API health
2. Verify workers are running
3. Submit test tasks
4. Monitor task completion
5. Test worker scaling

## Task Submission Example

```python
import aiohttp
import asyncio

async def submit_task():
    async with aiohttp.ClientSession() as session:
        task_data = {
            "problem_id": "test-problem-001",
            "parameters": {
                "max_steps": 10,
                "agent_config": {"name": "test-agent"}
            },
            "priority": 5
        }

        async with session.post(
            "http://localhost:8000/api/v1/tasks",
            json=task_data
        ) as resp:
            task = await resp.json()
            print(f"Task created: {task['id']}")

asyncio.run(submit_task())
```

## Worker Scaling Examples

```bash
# Scale to 10 workers
curl -X POST "http://localhost:8000/api/v1/workers/internal/scale?num_workers=10"

# Check worker status
curl "http://localhost:8000/api/v1/workers/internal/status"

# Stop all workers
curl -X POST "http://localhost:8000/api/v1/workers/internal/stop"
```

## Development

```bash
# Run tests
make test

# TDD mode
make tdd

# Format code
poetry run black src/

# Type check
poetry run pyright src/
```

## Database Schema

- **tasks**: Task queue and execution results
- **workers**: Worker registration and status
- **task_logs**: Detailed task execution logs

## Architecture Benefits

The integrated worker approach provides:

1. **Simplicity**: Single process to manage
2. **Efficiency**: Shared memory and resources
3. **Control**: Direct API control over workers
4. **Monitoring**: Unified logs and metrics
5. **Deployment**: Easier containerization and deployment
