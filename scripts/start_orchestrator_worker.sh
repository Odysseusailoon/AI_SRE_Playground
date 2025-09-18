#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/tmp"
mkdir -p "$LOG_DIR"

WORKER_ID="${WORKER_ID:-worker-100-kind}"
BACKEND="${BACKEND:-orchestrator}"
API_URL="${API_URL:-http://localhost:8000}"
SUPPORTED_PROBLEMS="${SUPPORTED_PROBLEMS:-misconfig_app_hotel_res-detection-1}"
HEALTH_TIMEOUT="${WORKER_CHECK_TIMEOUT:-30}"

LOG_FILE="$LOG_DIR/worker_${WORKER_ID}.log"
PID_FILE="$LOG_DIR/worker_${WORKER_ID}.pid"

if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ROOT_DIR/.env" | xargs -I{} echo {})
fi

existing=$(pgrep -f "worker.py --id $WORKER_ID" || true)
if [[ -n "$existing" ]]; then
  echo "[start_worker] Existing worker process found ($existing); stopping"
  echo "$existing" | xargs -r kill
  sleep 1
fi

register_payload="{\"worker_id\": \"$WORKER_ID\", \"backend_type\": \"$BACKEND\", \"capabilities\": {\"max_parallel_tasks\": 1, \"supported_problems\": [\"$SUPPORTED_PROBLEMS\"]}, \"metadata\": {\"type\": \"$BACKEND\", \"host\": \"$(hostname)\"}}"

curl -sf -X POST "$API_URL/api/v1/workers/register" \
  -H "Content-Type: application/json" \
  -d "$register_payload" >/dev/null || true

cd "$ROOT_DIR"
nohup poetry run python task-executor/workers/src/worker.py \
  --id "$WORKER_ID" --backend "$BACKEND" --api "$API_URL" \
  >"$LOG_FILE" 2>&1 &
WORKER_PID=$!
echo $WORKER_PID > "$PID_FILE"

echo "[start_worker] Worker $WORKER_ID started with PID $WORKER_PID"

for ((i=0; i<HEALTH_TIMEOUT; i++)); do
  status=$(curl -sf "$API_URL/api/v1/workers/$WORKER_ID" 2>/dev/null || true)
  if [[ -n "$status" ]]; then
    echo "[start_worker] Worker registered: $status"
    exit 0
  fi
  if ! kill -0 "$WORKER_PID" >/dev/null 2>&1; then
    echo "[start_worker] Worker process exited unexpectedly. See $LOG_FILE"
    exit 1
  fi
  sleep 1
done

echo "[start_worker] Timeout waiting for worker to register"
exit 1
