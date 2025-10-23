#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_PARENT="$(dirname "${PROJECT_ROOT}")"
CACHE_DIR="${SCRIPT_DIR}/.cache"
ARTIFACTS_DIR="${SCRIPT_DIR}/artifacts"
STATE_FILE="${ARTIFACTS_DIR}/vm_state.env"
IMAGE_URL="${ROCKY_IMAGE_URL:-https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2}"
IMAGE_PATH="${CACHE_DIR}/$(basename "${IMAGE_URL}")"

SSH_FORWARD_PORT=${SSH_FORWARD_PORT:-2222}
HTTP_FORWARD_PORT=${HTTP_FORWARD_PORT:-10080}
SSH_PORT_RETRIES=${SSH_PORT_RETRIES:-300}
SSH_PORT_DELAY=${SSH_PORT_DELAY:-1}
SSH_CONNECT_RETRIES=${SSH_CONNECT_RETRIES:-90}
SSH_CONNECT_DELAY=${SSH_CONNECT_DELAY:-3}

TMPDIR=""
OVERLAY_IMAGE=""
SEED_IMAGE=""
QEMU_PIDFILE=""
QEMU_ACCEL="tcg"
QEMU_CPU="qemu64"
QEMU_CPU_FALLBACK=""

cleanup_on_error() {
  local exit_code=$?

  if [[ -n "${QEMU_PIDFILE}" && -f "${QEMU_PIDFILE}" ]]; then
    if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
      kill "$(cat "${QEMU_PIDFILE}")" >/dev/null 2>&1 || true
      sleep 2
      if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
        kill -9 "$(cat "${QEMU_PIDFILE}")" >/dev/null 2>&1 || true
      fi
    fi
    rm -f "${QEMU_PIDFILE}"
  fi

  [[ -n "${TMPDIR}" && -d "${TMPDIR}" ]] && rm -rf "${TMPDIR}"
  [[ -n "${OVERLAY_IMAGE}" && -f "${OVERLAY_IMAGE}" ]] && rm -f "${OVERLAY_IMAGE}"
  [[ -n "${SEED_IMAGE}" && -f "${SEED_IMAGE}" ]] && rm -f "${SEED_IMAGE}"

  rm -f "${STATE_FILE}"

  exit "${exit_code}"
}
trap cleanup_on_error ERR

mkdir -p "${CACHE_DIR}" "${ARTIFACTS_DIR}"

if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  if [[ -n "${QEMU_PIDFILE:-}" && -f "${QEMU_PIDFILE}" ]]; then
    if pgrep -F "${QEMU_PIDFILE}" >/dev/null 2>&1; then
      echo "Existing VM is still running (PID $(cat "${QEMU_PIDFILE}"))." >&2
      echo "Run ${SCRIPT_DIR}/stop_vm.sh before starting a new instance." >&2
      exit 1
    fi
  fi
  rm -f "${STATE_FILE}"
fi

if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  QEMU_ACCEL="kvm:tcg"
  QEMU_CPU="host"
  QEMU_CPU_FALLBACK="qemu64"
else
  echo ":: /dev/kvm unavailable, using software virtualization (TCG)"
fi

echo ":: Ensuring Rocky Linux cloud image is present"
if [[ ! -f "${IMAGE_PATH}" ]]; then
  curl -L -o "${IMAGE_PATH}" "${IMAGE_URL}"
fi

TMPDIR="$(mktemp -d "${ARTIFACTS_DIR}/vm-XXXXXX")"
USER_DATA="${TMPDIR}/user-data"
META_DATA="${TMPDIR}/meta-data"
SEED_IMAGE="${TMPDIR}/seed.iso"

cat > "${USER_DATA}" <<'EOF'
#cloud-config
users:
  - name: ansible
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    lock_passwd: false
    passwd: $6$FNvHbKuCWtgI8xqO$g5/x.hgCbmZIp4YGm1OjeXvIPJQXDFlPeNW8bUxPODG1PrTnxSSiFovwqPOrW9X5yKjAiv0P1ugtNnwMW/Lb7/
ssh_pwauth: true
package_update: true
packages:
  - python3
  - python3-libselinux
  - python3-dnf
EOF

cat > "${META_DATA}" <<'EOF'
instance-id: ansible-haproxy-decision
local-hostname: rocky9-ci
EOF

echo ":: Creating cloud-init seed image"
cloud-localds "${SEED_IMAGE}" "${USER_DATA}" "${META_DATA}"

OVERLAY_IMAGE="${TMPDIR}/rocky9-overlay.qcow2"
qemu-img create -f qcow2 -F qcow2 -b "${IMAGE_PATH}" "${OVERLAY_IMAGE}" >/dev/null

QEMU_PIDFILE="${TMPDIR}/qemu.pid"

echo ":: Launching Rocky Linux VM"
launch_qemu() {
  qemu-system-x86_64 \
    -daemonize \
    -machine accel="${QEMU_ACCEL}" \
    -cpu "${QEMU_CPU}" \
    -smp 2 \
    -m 4096 \
    -drive if=virtio,file="${OVERLAY_IMAGE}",format=qcow2 \
    -drive if=virtio,file="${SEED_IMAGE}",format=raw \
    -netdev user,id=net0,hostfwd=tcp::${SSH_FORWARD_PORT}-:22,hostfwd=tcp::${HTTP_FORWARD_PORT}-:80 \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial none \
    -monitor none \
    -pidfile "${QEMU_PIDFILE}"
}

trap - ERR
set +e
launch_qemu
QEMU_EXIT=$?
set -e
trap cleanup_on_error ERR

if [[ ${QEMU_EXIT} -ne 0 && -n "${QEMU_CPU_FALLBACK}" ]]; then
  echo ":: Falling back to ${QEMU_CPU_FALLBACK}/${QEMU_ACCEL##*:}" >&2
  QEMU_CPU="${QEMU_CPU_FALLBACK}"
  QEMU_ACCEL="tcg"
  trap - ERR
  set +e
  launch_qemu
  QEMU_EXIT=$?
  set -e
  trap cleanup_on_error ERR
  if [[ ${QEMU_EXIT} -ne 0 ]]; then
    exit "${QEMU_EXIT}"
  fi
elif [[ ${QEMU_EXIT} -ne 0 ]]; then
  trap cleanup_on_error ERR
  exit "${QEMU_EXIT}"
fi
trap cleanup_on_error ERR

cat > "${STATE_FILE}" <<EOF
TMPDIR=${TMPDIR}
OVERLAY_IMAGE=${OVERLAY_IMAGE}
SEED_IMAGE=${SEED_IMAGE}
QEMU_PIDFILE=${QEMU_PIDFILE}
SSH_FORWARD_PORT=${SSH_FORWARD_PORT}
HTTP_FORWARD_PORT=${HTTP_FORWARD_PORT}
EOF

echo ":: Waiting for SSH to become available"
for attempt in $(seq 1 "${SSH_PORT_RETRIES}"); do
  if nc -z 127.0.0.1 "${SSH_FORWARD_PORT}" >/dev/null 2>&1; then
    break
  fi
  sleep "${SSH_PORT_DELAY}"
done

if ! nc -z 127.0.0.1 "${SSH_FORWARD_PORT}" >/dev/null 2>&1; then
  echo "SSH did not become ready in time after ${SSH_PORT_RETRIES} attempts" >&2
  exit 1
fi

echo ":: Validating SSH connectivity"
for attempt in $(seq 1 "${SSH_CONNECT_RETRIES}"); do
  if sshpass -p ansible ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${SSH_FORWARD_PORT}" ansible@127.0.0.1 "true" >/dev/null 2>&1; then
    break
  fi
  sleep "${SSH_CONNECT_DELAY}"
done

if ! sshpass -p ansible ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "${SSH_FORWARD_PORT}" ansible@127.0.0.1 "true" >/dev/null 2>&1; then
  echo "Unable to establish SSH session with guest after ${SSH_CONNECT_RETRIES} attempts" >&2
  exit 1
fi

trap - ERR
echo ":: VM is ready (SSH on ${SSH_FORWARD_PORT})"
