#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
API_DIR="${SCRIPT_DIR}/api"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -d "${API_DIR}" ]]; then
  echo "[start_api] error: expected api directory at ${API_DIR}" >&2
  exit 1
fi

: "${UVICORN_WORKERS:=$(python3 - <<'PY'
import multiprocessing
print(max(8, multiprocessing.cpu_count()))
PY
)}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

if [[ -f "${ENV_FILE}" ]]; then
  # Export variables from repo-level .env so downstream code picks up model/API settings
  set -a
  source "${ENV_FILE}"
  set +a
fi

cd "${API_DIR}"
poetry run uvicorn src.main:app --host "${HOST}" --port "${PORT}" --workers "${UVICORN_WORKERS}" "$@"
