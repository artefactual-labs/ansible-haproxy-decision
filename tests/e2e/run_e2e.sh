#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_PARENT="$(dirname "${PROJECT_ROOT}")"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
STATE_FILE="${ARTIFACTS_DIR}/vm_state.env"
START_SCRIPT="${SCRIPT_DIR}/start_vm.sh"
SMOKE_SCRIPT="${SCRIPT_DIR}/run_smoke.sh"

source "${SCRIPT_DIR}/lib.sh"

SKIP_CLEANUP=${SKIP_CLEANUP:-0}
KEEP_VM_RUNNING_RAW=${VM_NO_SHUTDOWN:-${vm_no_shutdown:-0}}
case "${KEEP_VM_RUNNING_RAW}" in
  1|true|TRUE|True|yes|YES|Yes) KEEP_VM_RUNNING=1 ;;
  *) KEEP_VM_RUNNING=0 ;;
esac

cleanup() {
  if [[ "${SKIP_CLEANUP}" -eq 1 ]]; then
    if [[ -n "${QEMU_PIDFILE:-}" && -f "${QEMU_PIDFILE}" ]]; then
      if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
        echo ":: Leaving VM running for debugging (PID $(cat "${QEMU_PIDFILE}"))"
      fi
    fi
    return
  fi

  if [[ -n "${QEMU_PIDFILE:-}" && -f "${QEMU_PIDFILE}" ]]; then
    if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
      kill "$(cat "${QEMU_PIDFILE}")" >/dev/null 2>&1 || true
      sleep 2
      if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
        kill -9 "$(cat "${QEMU_PIDFILE}")" >/dev/null 2>&1 || true
      fi
    fi
    rm -f "${QEMU_PIDFILE}"
  fi

  [[ -n "${TMPDIR:-}" && -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}"
  [[ -n "${OVERLAY_IMAGE:-}" && -f "${OVERLAY_IMAGE}" ]] && rm -f "${OVERLAY_IMAGE}"
  [[ -n "${SEED_IMAGE:-}" && -f "${SEED_IMAGE}" ]] && rm -f "${SEED_IMAGE}"

  rm -f "${STATE_FILE}"
}

echo ":: Starting test VM for local e2e run"
"${START_SCRIPT}"

load_vm_state

if [[ "${KEEP_VM_RUNNING}" -eq 1 ]]; then
  SKIP_CLEANUP=1
fi

trap cleanup EXIT

export ANSIBLE_ROLES_PATH="${PROJECT_PARENT}:${HOME}/.ansible/roles"

galaxy_retry() {
  local cmd="$1"
  local retries=${2:-5}
  local delay=${3:-10}
  local attempt=1
  while true; do
    if eval "$cmd"; then
      return 0
    fi
    if [[ $attempt -ge $retries ]]; then
      echo "Command failed after ${attempt} attempts: $cmd" >&2
      return 1
    fi
    echo "Retrying in ${delay}s... (${attempt}/${retries})"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

echo ":: Installing Ansible Galaxy roles"
galaxy_retry "ansible-galaxy role install -r '${SCRIPT_DIR}/requirements.yml'" "${GALAXY_RETRIES:-5}" "${GALAXY_DELAY:-10}"

echo ":: Installing Ansible Galaxy collections"
galaxy_retry "ansible-galaxy collection install -r '${SCRIPT_DIR}/requirements.yml'" "${GALAXY_RETRIES:-5}" "${GALAXY_DELAY:-10}"

echo ":: Running Ansible playbook"
ANSIBLE_EXIT=0
ANSIBLE_STDOUT_CALLBACK=debug ansible-playbook \
  -i "${SCRIPT_DIR}/inventory.ini" \
  "${SCRIPT_DIR}/site.yml" || ANSIBLE_EXIT=$?

if [[ "${ANSIBLE_EXIT}" -ne 0 ]]; then
  echo ":: Ansible playbook failed with exit code ${ANSIBLE_EXIT}"
  if [[ "${KEEP_VM_ON_FAILURE:-1}" -ne 0 ]]; then
    SKIP_CLEANUP=1
    echo ":: VM is still running for debugging."
    echo ":: SSH with: sshpass -p ansible ssh -p ${SSH_FORWARD_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@127.0.0.1"
    echo ":: When finished, run ${SCRIPT_DIR}/stop_vm.sh to shut it down."
    exit "${ANSIBLE_EXIT}"
  else
    exit "${ANSIBLE_EXIT}"
  fi
fi

"${SMOKE_SCRIPT}" 10

if [[ "${KEEP_VM_RUNNING}" -eq 1 ]]; then
  echo ":: VM left running as requested (SSH on port ${SSH_FORWARD_PORT})"
  echo "   Connect with: sshpass -p ansible ssh -p ${SSH_FORWARD_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@127.0.0.1"
  echo "   When finished, run ${SCRIPT_DIR}/stop_vm.sh to clean up."
else
  echo ":: Powering off VM"
  remote_ssh sudo /sbin/poweroff || true
  sleep 5
fi
