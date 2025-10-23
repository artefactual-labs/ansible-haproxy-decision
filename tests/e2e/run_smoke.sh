#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
METRICS_FILE="${ARTIFACTS_DIR}/haproxy_metrics.prom"
REMOTE_K6_SCRIPT=/home/ansible/k6_smoke.js

source "${SCRIPT_DIR}/lib.sh"

load_vm_state

WAIT_SECONDS=${1:-10}

echo ":: Waiting for HAProxy to settle (${WAIT_SECONDS}s)"
sleep "${WAIT_SECONDS}"

if ensure_remote_k6; then
  if remote_scp "${SCRIPT_DIR}/k6/smoke.js" "${REMOTE_USER}@127.0.0.1:${REMOTE_K6_SCRIPT}"; then
    if ! remote_ssh BASE_URL=http://127.0.0.1 k6 run "${REMOTE_K6_SCRIPT}"; then
      echo "k6 smoke test failed" >&2
    fi
  else
    echo "Failed to copy k6 smoke script to guest; skipping smoke test." >&2
  fi
else
  echo "k6 installation failed on guest; skipping smoke test." >&2
fi

mkdir -p "${ARTIFACTS_DIR}"
echo ":: Collecting HAProxy Prometheus metrics"
collect_prometheus_metrics "${METRICS_FILE}"
