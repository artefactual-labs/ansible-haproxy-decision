#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/artifacts/vm_state.env"
REMOTE_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
REMOTE_USER=${REMOTE_USER:-ansible}
REMOTE_PASSWORD=${REMOTE_PASSWORD:-ansible}

load_vm_state() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "VM state file not found at ${STATE_FILE}" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "${STATE_FILE}"

  : "${SSH_FORWARD_PORT:?SSH_FORWARD_PORT missing in state file}"
  : "${HTTP_FORWARD_PORT:?HTTP_FORWARD_PORT missing in state file}"
  : "${QEMU_PIDFILE:?QEMU_PIDFILE missing in state file}"
  : "${TMPDIR:?TMPDIR missing in state file}"
  : "${OVERLAY_IMAGE:?OVERLAY_IMAGE missing in state file}"
  : "${SEED_IMAGE:?SEED_IMAGE missing in state file}"
}

remote_ssh() {
  sshpass -p "${REMOTE_PASSWORD}" ssh "${REMOTE_SSH_OPTS[@]}" -p "${SSH_FORWARD_PORT}" "${REMOTE_USER}"@127.0.0.1 "$@"
}

remote_scp() {
  sshpass -p "${REMOTE_PASSWORD}" scp "${REMOTE_SSH_OPTS[@]}" -P "${SSH_FORWARD_PORT}" "$@"
}

ensure_remote_k6() {
  if remote_ssh command -v k6 >/dev/null 2>&1; then
    return 0
  fi

  if remote_ssh command -v apt-get >/dev/null 2>&1; then
    echo ":: Installing k6 via Grafana APT repository (guest)"
    remote_ssh sudo apt-get update || return 1
    remote_ssh sudo apt-get install -y ca-certificates curl gnupg || return 1
    remote_ssh sudo mkdir -p /usr/share/keyrings || return 1
    remote_ssh "curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/k6-archive-keyring.gpg" || return 1
    remote_ssh "printf '%s\n' 'deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main' | sudo tee /etc/apt/sources.list.d/k6.list >/dev/null" || return 1
    remote_ssh sudo apt-get update || return 1
    remote_ssh sudo apt-get install -y k6 || return 1
    return 0
  fi

  if remote_ssh command -v dnf >/dev/null 2>&1; then
    echo ":: Installing k6 via Grafana RPM repository (guest)"
    remote_ssh sudo dnf install -y https://dl.k6.io/rpm/repo.rpm || return 1
    remote_ssh sudo dnf install -y k6 || return 1
    return 0
  fi

  echo "Unable to determine package manager on guest to install k6" >&2
  return 1
}

collect_prometheus_metrics() {
  local target_file=$1
  if remote_ssh curl -fs http://127.0.0.1:8404/metrics > "${target_file}"; then
    grep -E 'haproxy_frontend_http_requests_total\{.*proxy="public_http"' "${target_file}" || true
    grep -E 'haproxy_backend_http_responses_total\{.*proxy="varnish_backend".*code="2xx"' "${target_file}" || true
    grep -E 'haproxy_server_http_responses_total\{.*proxy="nginx_backend".*code="2xx"' "${target_file}" || true
  else
    echo "Unable to scrape HAProxy metrics endpoint" >&2
  fi
}
