# Task Executor

AIOpsLab Task Executor implements the REST API and worker orchestration described in `specs/002-online-rl-data`. It queues AIOpsLab problems, executes them via orchestrators, and retains full logs and LLM conversations for online RL datasets.

## Highlights
- FastAPI application backed by PostgreSQL, exposing `/api/v1` endpoints for task lifecycle, workers, and conversation data.
- Database queue uses `SELECT ... FOR UPDATE SKIP LOCKED` with priority and `backend_type` filtering to dispatch work safely across workers.
- Integrated `WorkerManager` spins up orchestrator-backed workers inside the API process and tracks timeouts via a background task.
- LLM interactions, task logs, and worker metrics are persisted for downstream RL pipelines and can be exported through REST or `scripts/export_task_data.py`.
- Open API (no auth) with health checks, queue statistics, and optional Prometheus metrics for observability.

## QuickStart
1. **Bring up PostgreSQL (one time):**
   ```bash
   cd task-executor
   docker compose up -d postgres     # or: make db-up
   ```

2. **Install dependencies and start the dev API (internal workers included):**
   ```bash
   cd task-executor/api
   poetry install

   # Ensure the repo-level .env defines DATABASE_URL and any LLM credentials (see Configuration Notes)
   poetry run uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
   ```

3. **Submit a sample experiment task:**
   ```bash
   curl -X POST http://localhost:8000/api/v1/tasks \
     -H "Content-Type: application/json" \
     -d '{
           "problem_id": "k8s_target_port-misconfig-detection-1",
           "parameters": {
             "backend_type": "orchestrator",
             "max_steps": 25,
             "agent_config": {"model": "gpt-5-mini"}
           }
         }'
   ```

4. **Inspect task status and logs:**
   ```bash
   # Assume the returned task ID is stored in $TASK_ID
   curl http://localhost:8000/api/v1/tasks/$TASK_ID
   curl "http://localhost:8000/api/v1/tasks/$TASK_ID/logs?limit=50"
   ```

5. **Verify data persisted to the queue and LLM tables:**
   ```bash
   curl http://localhost:8000/api/v1/tasks/stats
   curl "http://localhost:8000/api/v1/llm-conversations?task_id=$TASK_ID"
   curl http://localhost:8000/queue/stats
   ```

6. **Optional – export the RL dataset snapshot:**
   ```bash
   cd task-executor
   scripts/export_task_data.py http://localhost:8000 --output tmp/export.json
   ```

These steps give you a local dev loop: start the API with integrated orchestrator workers, run an end-to-end task, and confirm that tasks, logs, and conversation artifacts land in PostgreSQL.

## Current Design Snapshot (2025-09-18)
- ✅ Task CRUD, queue stats, log retrieval, worker registration/claim, and LLM conversation APIs are wired up and usable against PostgreSQL.
- ✅ Internal workers auto-register as `worker-###-kind`, run the real AIOpsLab `OrchestratorExecutor`, and honour timeout/background settings from `config.settings`.
- ✅ Background `check_timeouts_periodically` enforces the 30-minute default timeout and records failure logs.
- ⚠️ `GET /metrics` currently raises `AttributeError: __aenter__` because `metrics_endpoint` calls `async with get_db()` on a dependency generator.
- ⚠️ Worker `complete`/`fail` endpoints accept any `worker_id` and do not validate ownership against `task.worker_id`.
- ⚠️ Long-running orchestrator subprocess calls execute on the main event loop and can stall other requests until they finish.

## Layout
```
task-executor/
├── api/                     # FastAPI app (Poetry project)
│   ├── src/
│   │   ├── main.py          # app + lifespan
│   │   ├── api/             # routers (tasks, workers, conversations, health)
│   │   ├── config/          # pydantic settings, logging helpers
│   │   ├── middleware/      # request ID + error handling
│   │   ├── models/          # SQLAlchemy models & enums
│   │   ├── monitoring/      # Prometheus integration
│   │   ├── services/        # task/worker business logic
│   │   └── workers/         # in-process orchestrator executor stack
│   └── tests/
├── workers/                 # Optional standalone worker client
├── QUICK_START.md           # Makefile-driven developer flow
├── start_api.sh             # Helper launcher that loads repo-level .env
└── quick_test.sh            # Smoke tester for API + workers
```

## Task Lifecycle
1. Client `POST /api/v1/tasks` with `problem_id` and optional `parameters`; defaults (`max_steps`, `timeout_minutes`, `priority`, `agent_config.model`) are applied.
2. Tasks persist as `pending` rows in PostgreSQL; `backend_type` in `parameters` constrains which workers can claim them.
3. Workers register via `POST /api/v1/workers/register`; `WorkerManager` auto-registers N internal orchestrator workers at startup.
4. Workers call `POST /api/v1/workers/{id}/claim`; the queue marks the task `running`, locks the row, and attaches `worker_id`.
5. Execution writes streaming logs (`task_logs` table) and LLM turns (`llm_conversations`), then workers call `.../complete` or `.../fail`.
6. Background timeout checker converts overstayed `running` tasks to `timeout` and records the failure context.

## API Surface

### Tasks
- `POST /api/v1/tasks` create task.
- `GET /api/v1/tasks` list with status/problem/worker filters and pagination.
- `GET /api/v1/tasks/{uuid}` fetch detail.
- `POST /api/v1/tasks/{uuid}/cancel` cancel pending/running tasks.
- `GET /api/v1/tasks/{uuid}/logs` retrieve recent logs (filter by level, limit).
- `GET /api/v1/tasks/stats` aggregate counts, success rate, per-problem breakdown.

### Workers
- `POST /api/v1/workers/register` upsert worker metadata and capability set (`supported_problems`, `max_parallel_tasks`).
- `GET /api/v1/workers` and `GET /api/v1/workers/{id}` list/inspect workers.
- `POST /api/v1/workers/{id}/heartbeat` refresh status and current task pointer.
- `POST /api/v1/workers/{id}/claim` atomically claim next eligible task.
- `POST /api/v1/workers/{id}/tasks/{task_id}/complete|fail` finish execution.
- `GET /api/v1/workers/{id}/stats` compute success rate and average runtime.

### Internal Worker Control
- `GET /api/v1/workers/internal/status` report `WorkerManager` state.
- `POST /api/v1/workers/internal/scale?num_workers=N` adjust in-process worker count (0-50).
- `POST /api/v1/workers/internal/start|stop` restart or halt internal workers.

### LLM Conversations
- `GET /api/v1/llm-conversations` list sessions (filter by task/model, paginate).
- `GET /api/v1/llm-conversations/{conversation_id}` fetch full message history.
- `GET /api/v1/llm-conversations/task/{task_id}/conversations` list all sessions per task.
- `GET /api/v1/llm-conversations/{conversation_id}/messages` filter messages by role.
- `GET /api/v1/llm-conversations/stats/summary` aggregate token counts and success ratio.

### Health & Monitoring
- `GET /health` composite health (DB latency, worker counts, queue snapshot).
- `GET /queue/stats` compute wait time, execution time, and status totals.
- `GET /metrics` (Prometheus exposition; see limitations above).
- `GET /` root metadata, `/docs` & `/redoc` if `ENABLE_DOCS`.

## Quick Start
```bash
# 1. Start PostgreSQL (or make db-up)
docker compose up -d postgres

# 2. Install API dependencies
cd task-executor/api
poetry install

# 3. Provide credentials for orchestrator agents (repo-level .env)
cat <<'ENV' > ../.env
DATABASE_URL=postgresql+asyncpg://aiopslab:aiopslab@localhost:5432/aiopslab
NUM_INTERNAL_WORKERS=3
AUTO_START_WORKERS=true
ENABLE_BACKGROUND_TASKS=true
OPENAI_API_KEY=sk-...
# or OPENROUTER_API_KEY=...
DEFAULT_AGENT_MODEL=gpt-4o
ENV

# 4. Ensure Kind + kubectl + Docker are installed if you want real orchestrator runs
#    kubectl context 'kind-aiopslab-worker-###' will be created per worker.

# 5. Launch the API (workers auto-start)
poetry run uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
# or from repo root:
../start_api.sh
```

Submit a sample task once the server reports healthy:

```bash
curl -X POST http://localhost:8000/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "problem_id": "k8s_target_port-misconfig-detection-1",
    "parameters": {
      "backend_type": "orchestrator",
      "max_steps": 25,
      "priority": 7,
      "agent_config": {"model": "gpt-4o-mini"}
    }
  }'
```

## Configuration Notes
- `DATABASE_URL`: asyncpg DSN; default `postgresql+asyncpg://aiopslab:aiopslab@localhost:5432/aiopslab`.
- Worker toggles: `NUM_INTERNAL_WORKERS`, `AUTO_START_WORKERS`, `ENABLE_BACKGROUND_TASKS` manage in-process workers.
- Task defaults: `DEFAULT_TIMEOUT_MINUTES`, `DEFAULT_MAX_STEPS`, `DEFAULT_PRIORITY` applied when clients omit values.
- Scheduling cadence: `TIMEOUT_CHECK_INTERVAL`, `WORKER_POLL_INTERVAL`, `WORKER_HEARTBEAT_TIMEOUT` tune queue behaviour.
- LLM credentials: `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `DEFAULT_AGENT_MODEL` feed the GPT-based orchestrator agent.
- Settings live in `api/src/config/settings.py`; repo-level `.env` is loaded by default.

## Data Model
- `tasks`: queue plus execution metadata (`status`, `result`, `error_details`, timings, worker binding).
- `task_logs`: append-only execution log entries with level, timestamp, and context JSON.
- `workers`: registered workers with capabilities, status, heartbeat, lifecycle counters.
- `llm_conversations`: persisted dialogue transcripts, tokens, cost estimates, and metadata (problem_id, worker_id, kind cluster).
- JSONB indexes support querying by `parameters`, `result`, and conversation metadata for RL analytics.

## Worker Integration Notes
- Worker IDs must match `worker-###-kind`; internal workers register as `worker-00X-kind` while their background task names use `-internal`.
- `TaskQueue` enforces backend affinity: tasks that set `parameters.backend_type` will only be claimed by workers advertising the same `backend_type`.
- Capability hints (`supported_problems`) convey problem eligibility; matching today is simple substring containment.
- External workers can reuse `workers/src/worker.py` or any client that follows register → heartbeat → claim → complete/fail.

## Observability & Data Export
- Structured JSON logging via `config.logging` with request IDs and event names.
- `scripts/export_task_data.py` pulls tasks, logs, and conversation payloads for downstream RL dataset generation.
- `llm_logging_agent` captures tool calls and agent turns; messages can be fetched via REST for fine-grained replay.
- Health/queue endpoints allow dashboards; once fixed, `/metrics` will expose Prometheus counters and gauges (`task_queue_size`, `worker_count`, latency histograms).

## Spec Coverage (`specs/002-online-rl-data`)
- REST endpoints cover task submission, status polling, cancellation, worker management, and dataset retrieval needs.
- Workers poll the DB queue with `SELECT ... SKIP LOCKED`, honour backend affinities, and isolate execution per Kind cluster.
- States follow `pending → running → completed|failed|timeout|cancelled`, with automatic timeout enforcement and permanent storage of artifacts.
- LLM sessions and execution logs persist for every run, satisfying online RL dataset requirements and allowing export without data loss.
- No authentication layer is enabled, matching the spec’s assumption for internal experimentation.

## Known Limitations & TODOs
- Repair the Prometheus middleware session usage so `/metrics` works under async contexts.
- Harden worker status transitions by verifying `task.worker_id == worker_id` during `complete` and `fail`.
- Move orchestrator interactions (Kind cluster management, subprocesses) onto dedicated executors to avoid blocking the event loop.
- Add automated coverage (`api/tests`) around LLM conversation endpoints and timeout edge cases before promoting to production.
