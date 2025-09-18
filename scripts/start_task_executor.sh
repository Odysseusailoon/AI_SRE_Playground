#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/task-executor/api"
LOG_DIR="$ROOT_DIR/tmp"

PORT="${PORT:-8000}"
TIMEOUT="${STARTUP_TIMEOUT:-60}"

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/task_executor.log"
PID_FILE="$LOG_DIR/task_executor.pid"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ROOT_DIR/.env" | xargs -I{} echo {})
fi

export AUTO_START_WORKERS="${AUTO_START_WORKERS:-true}"
export ENABLE_BACKGROUND_TASKS="${ENABLE_BACKGROUND_TASKS:-true}"
export DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://aiopslab:aiopslab@localhost:5432/aiopslab}"

existing_pids=$(lsof -t -i :"$PORT" 2>/dev/null || true)
if [[ -n "$existing_pids" ]]; then
  echo "[start_task_executor] Port $PORT already in use by PID(s): $existing_pids. Terminating..."
  echo "$existing_pids" | xargs -r kill
  sleep 1
fi

echo "[start_task_executor] Starting Task Executor on port $PORT"

cd "$API_DIR"

nohup poetry run uvicorn src.main:app --host 0.0.0.0 --port "$PORT" \
  >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"

echo "[start_task_executor] PID $SERVER_PID";

health_url="http://127.0.0.1:$PORT/health"
for ((i=0; i<TIMEOUT; i++)); do
  if curl -sf "$health_url" >/dev/null 2>&1; then
    echo "[start_task_executor] Server is healthy (checked $health_url)"
    exit 0
  fi
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "[start_task_executor] Process $SERVER_PID exited unexpectedly. See $LOG_FILE"
    exit 1
  fi
  sleep 1
done

echo "[start_task_executor] Timeout waiting for server to become healthy. See $LOG_FILE"
exit 1
