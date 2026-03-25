#!/bin/bash

set -euo pipefail

readonly IOS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${IOS_SCRIPT_DIR}/../.." && pwd)"
readonly DEFAULT_LOOP_DIR="${REPO_ROOT}/.build/completion-loop/$(date -u +%Y%m%dT%H%M%SZ)"
export BLINK_COMPLETION_LOOP_DIR="${BLINK_COMPLETION_LOOP_DIR:-${DEFAULT_LOOP_DIR}}"

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

log() {
  printf '[%s] %s\n' "$(timestamp_utc)" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(timestamp_utc)" "$*" >&2
}

fail() {
  printf '[%s] ERROR: %s\n' "$(timestamp_utc)" "$*" >&2
  exit 1
}

ensure_dir() {
  mkdir -p "$1"
}

artifact_dir() {
  local gate="$1"
  local path="${BLINK_COMPLETION_LOOP_DIR}/${gate}"
  ensure_dir "${path}"
  printf '%s\n' "${path}"
}

report_path() {
  printf '%s\n' "${BLINK_COMPLETION_LOOP_DIR}/report.json"
}

ensure_report() {
  ensure_dir "${BLINK_COMPLETION_LOOP_DIR}"
  python3 "${IOS_SCRIPT_DIR}/report.py" init --report "$(report_path)" --repo-root "${REPO_ROOT}" >/dev/null
}

report_gate() {
  ensure_report
  python3 "${IOS_SCRIPT_DIR}/report.py" add \
    --report "$(report_path)" \
    --gate "$1" \
    --status "$2" \
    --command "$3" \
    --duration "$4" \
    --notes "$5" \
    --artifacts "$6" \
    --requires-manual "$7" \
    --lane "${8:-}" \
    --resource-group "${9:-}" \
    --worker "${10:-}" \
    --coverage-mode "${11:-}"
}

report_lane_metadata() {
  local metadata_file="$1"
  [[ -f "${metadata_file}" ]] || fail "Lane metadata file not found: ${metadata_file}"

  ensure_report
  python3 - "$(report_path)" "${metadata_file}" <<'PY'
import json
from datetime import datetime, timezone
from pathlib import Path
import sys

report_path = Path(sys.argv[1])
metadata_path = Path(sys.argv[2])

if report_path.exists():
    report = json.loads(report_path.read_text())
else:
    report = {
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_root": "",
        "entries": [],
    }

metadata = json.loads(metadata_path.read_text())
report.setdefault("entries", [])
report["entries"].append(
    {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "gate": metadata.get("gate", ""),
        "status": metadata.get("status", ""),
        "command": metadata.get("command", ""),
        "duration_sec": float(metadata.get("duration_sec", 0)),
        "notes": metadata.get("notes", ""),
        "artifacts": metadata.get("artifacts", []),
        "requires_manual": bool(metadata.get("requires_manual", False)),
        "lane": metadata.get("lane", ""),
        "resource_group": metadata.get("resource_group", ""),
        "worker": metadata.get("worker", ""),
        "coverage_mode": metadata.get("coverage_mode", ""),
    }
)
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
PY
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

team_id() {
  awk -F'=' '/^[[:space:]]*TEAM_ID[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "${REPO_ROOT}/developer_setup.xcconfig"
}

bundle_id() {
  awk -F'=' '/^[[:space:]]*BUNDLE_ID[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "${REPO_ROOT}/developer_setup.xcconfig"
}

local_host_name() {
  local value
  value="$(scutil --get LocalHostName 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(hostname -s)"
  fi
  printf '%s\n' "${value}"
}

fixture_device_host() {
  printf '%s\n' "${FIXTURE_DEVICE_HOST:-$(local_host_name).local}"
}

fixture_ssh_port() {
  printf '%s\n' "${FIXTURE_SSH_PORT:-2222}"
}

fixture_mosh_port() {
  printf '%s\n' "${FIXTURE_MOSH_PORT:-2223}"
}

default_simulator_name() {
  printf '%s\n' "${SIMULATOR_NAME:-iPad mini (A17 Pro)}"
}

resolve_simulator_id() {
  local simulator_name
  local simctl_json
  simulator_name="$(default_simulator_name)"
  simctl_json="$(mktemp)"
  xcrun simctl list devices available -j > "${simctl_json}"
  python3 - "${simulator_name}" "${simctl_json}" <<'PY'
import json
from pathlib import Path
import sys

target_name = sys.argv[1]
data = json.loads(Path(sys.argv[2]).read_text())
candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name") == target_name:
            candidates.append(device["udid"])
if candidates:
    print(candidates[0])
    sys.exit(0)

fallback = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPad"):
            fallback.append(device["udid"])
if fallback:
    print(fallback[0])
    sys.exit(0)

sys.exit(1)
PY
  local status=$?
  rm -f "${simctl_json}"
  return "${status}"
}

resolve_device_id() {
  local devicectl_json
  if [[ -n "${DEVICE_ID:-}" ]]; then
    printf '%s\n' "${DEVICE_ID}"
    return 0
  fi

  devicectl_json="$(mktemp)"
  xcrun devicectl list devices --json-output "${devicectl_json}" >/dev/null
  python3 - "${devicectl_json}" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

def walk(node):
    if isinstance(node, dict):
        if {"identifier", "deviceProperties"} <= set(node):
            yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)

def load_payload(path):
    return json.loads(Path(path).read_text())

def collect_devices(payload):
    connected_devices = []
    paired_but_disconnected = []
    for item in walk(payload):
        props = item.get("deviceProperties", {})
        hardware = item.get("hardwareProperties", {})
        connection = item.get("connectionProperties", {})

        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("reality") != "physical":
            continue
        if connection.get("pairingState") not in (None, "paired"):
            continue

        identifier = hardware.get("udid", item["identifier"])
        name = props.get("name", identifier)
        tunnel_state = connection.get("tunnelState")
        transport = connection.get("transportType")
        ddi_services = bool(props.get("ddiServicesAvailable"))

        is_connected = (
            tunnel_state == "connected"
            or transport == "wired"
            or ddi_services
        )

        if is_connected:
            connected_devices.append((identifier, name))
        else:
            paired_but_disconnected.append(
                (identifier, name, transport or "unknown", tunnel_state or "unknown")
            )
    return connected_devices, paired_but_disconnected

payload_path = sys.argv[1]
connected_devices, paired_but_disconnected = collect_devices(load_payload(payload_path))

if not connected_devices and paired_but_disconnected:
    for identifier, _, _, _ in paired_but_disconnected:
        subprocess.run(
            ["xcrun", "devicectl", "device", "info", "details", "--device", identifier],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    subprocess.run(
        ["xcrun", "devicectl", "list", "devices", "--json-output", payload_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    connected_devices, paired_but_disconnected = collect_devices(load_payload(payload_path))

if len(connected_devices) == 1:
    print(connected_devices[0][0])
    sys.exit(0)

if not connected_devices:
    if paired_but_disconnected:
        print("No connected physical iOS devices found. Paired but disconnected devices:", file=sys.stderr)
        for identifier, name, transport, tunnel_state in paired_but_disconnected:
            print(
                f"  {identifier}  {name}  transport={transport} tunnel={tunnel_state}",
                file=sys.stderr,
            )
        sys.exit(2)
    print("No connected physical iOS devices found.", file=sys.stderr)
    sys.exit(2)

print("Multiple connected physical iOS devices found. Set DEVICE_ID explicitly:", file=sys.stderr)
for identifier, name in connected_devices:
    print(f"  {identifier}  {name}", file=sys.stderr)
sys.exit(3)
PY
  local status=$?
  rm -f "${devicectl_json}"
  return "${status}"
}

run_logged() {
  local logfile="$1"
  shift
  "$@" > >(tee "${logfile}") 2>&1
}
