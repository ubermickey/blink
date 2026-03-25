#!/bin/bash

set -euo pipefail

fixture_timestamp_run_id() {
  date -u +%Y%m%dT%H%M%SZ
}

fixture_sanitize_token() {
  local raw="${1:-}"
  local fallback="${2:-default}"
  local value

  value="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
  value="${value#-}"
  value="${value%-}"
  if [[ -z "${value}" ]]; then
    value="${fallback}"
  fi
  printf '%s\n' "${value}"
}

fixture_isolation_enabled() {
  if [[ -n "${FIXTURE_LANE:-}" || -n "${FIXTURE_RUN_ID:-}" || -n "${FIXTURE_REMOTE_ROOT:-}" ]]; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

fixture_resolved_lane() {
  printf '%s\n' "${FIXTURE_LANE:-default}"
}

fixture_resolved_run_id() {
  if [[ -n "${FIXTURE_RUN_ID:-}" ]]; then
    printf '%s\n' "${FIXTURE_RUN_ID}"
    return 0
  fi
  printf '%s\n' "$(fixture_timestamp_run_id)"
}

fixture_default_remote_root() {
  local isolated="${1:-0}"
  local run_id="${2:-legacy}"
  local lane="${3:-default}"
  if [[ "${isolated}" == "1" ]]; then
    printf '%s\n' "~/fps-runs/${run_id}/${lane}"
  else
    printf '%s\n' "~/fps"
  fi
}

fixture_resolve_container_name() {
  local isolated="${1:-0}"
  local lane="${2:-default}"
  local run_id="${3:-legacy}"
  local base="${FIXTURE_CONTAINER_PREFIX:-blink-ssh-fixture}"

  if [[ -n "${FIXTURE_CONTAINER_NAME:-}" ]]; then
    printf '%s\n' "${FIXTURE_CONTAINER_NAME}"
    return 0
  fi

  if [[ "${isolated}" != "1" ]]; then
    printf '%s\n' "${base}"
    return 0
  fi

  local lane_tag run_tag
  lane_tag="$(fixture_sanitize_token "${lane}" "lane")"
  run_tag="$(fixture_sanitize_token "${run_id}" "run")"
  printf '%s\n' "${base}-${lane_tag}-${run_tag}"
}

fixture_pick_isolated_ports() {
  local run_id="${1:?missing run_id}"
  local lane="${2:?missing lane}"
  local start="${FIXTURE_PORT_RANGE_START:-34000}"
  local end="${FIXTURE_PORT_RANGE_END:-42000}"

  python3 - "${run_id}" "${lane}" "${start}" "${end}" <<'PY'
import hashlib
import socket
import sys

run_id, lane, raw_start, raw_end = sys.argv[1:5]
start = int(raw_start)
end = int(raw_end)
if start < 1024:
    start = 1024
if end <= start + 1:
    print("Invalid fixture port range", file=sys.stderr)
    sys.exit(2)
if start % 2 == 1:
    start += 1
if end % 2 == 0:
    end -= 1
if end <= start:
    print("Invalid fixture port range after normalization", file=sys.stderr)
    sys.exit(2)

slots = ((end - start) // 2) + 1
seed = int(hashlib.sha256(f"{run_id}:{lane}".encode("utf-8")).hexdigest(), 16)

def free(port: int) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        return False
    finally:
        sock.close()
    return True

for offset in range(slots):
    idx = (seed + offset) % slots
    ssh_port = start + (idx * 2)
    mosh_port = ssh_port + 1
    if free(ssh_port) and free(mosh_port):
        print(f"{ssh_port} {mosh_port}")
        sys.exit(0)

print("Unable to allocate free fixture SSH/Mosh ports", file=sys.stderr)
sys.exit(1)
PY
}
