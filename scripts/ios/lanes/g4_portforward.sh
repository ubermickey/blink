#!/bin/bash

set -euo pipefail

LANE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_SCRIPT_DIR="$(cd "${LANE_SCRIPT_DIR}/.." && pwd)"
source "${IOS_SCRIPT_DIR}/common.sh"

allow_no_fixture=0
ci_mode=0

for arg in "$@"; do
  case "${arg}" in
    --allow-no-fixture) allow_no_fixture=1 ;;
    --ci) ci_mode=1 ;;
    *) fail "Unknown argument: ${arg}" ;;
  esac
done

readonly LANE_NAME="g4_portforward"
readonly GATE_NAME="G4 Domain Gates"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-fixture}"
readonly WORKER="${LANE_WORKER:-gpt_5_3_codex__g4_ssh_mosh}"
readonly COVERAGE_MODE="${COVERAGE_MODE:-full}"
readonly COMMAND_DESC="xcodebuild -scheme BlinkQA test -only-testing:SSHTests/SSHPortForwardTests"
readonly LANE_DIR="$(artifact_dir "g4-domain-gates/${LANE_NAME}")"
readonly METADATA_PATH="${LANE_DIR}/lane-metadata.json"
readonly TEST_LOG="${LANE_DIR}/test.log"

start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

epoch_now() {
  python3 - <<'PY'
import time
print(time.time())
PY
}

write_metadata() {
  local status="$1"
  local notes="$2"
  local started="$3"
  local finished="$4"
  local simulator_id="$5"
  local fixture_host="$6"
  local fixture_port="$7"
  python3 - "${METADATA_PATH}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${WORKER}" "${RESOURCE_GROUP}" "${COVERAGE_MODE}" "${notes}" "${started}" "${finished}" "${simulator_id}" "${fixture_host}" "${fixture_port}" "${TEST_LOG}" "${COMMAND_DESC}" "${FIXTURE_PORTFORWARD_LOCAL_PORT}" "${FIXTURE_PORTFORWARD_REMOTE_PORT}" <<'PY'
import json
from pathlib import Path
import sys

(
    metadata_path,
    lane,
    gate,
    status,
    worker,
    resource_group,
    coverage_mode,
    notes,
    started,
    finished,
    simulator_id,
    fixture_host,
    fixture_port,
    test_log,
    command_desc,
    local_forward_port,
    remote_forward_port,
) = sys.argv[1:]

payload = {
    "lane": lane,
    "gate": gate,
    "status": status,
    "worker": worker,
    "resource_group": resource_group,
    "coverage_mode": coverage_mode,
    "requires_fixture": True,
    "requires_device": False,
    "notes": notes,
    "started_epoch": float(started),
    "finished_epoch": float(finished),
    "duration_sec": float(finished) - float(started),
    "simulator_id": simulator_id,
    "fixture_host": fixture_host,
    "fixture_port": fixture_port,
    "fixture_portforward_local_port": local_forward_port,
    "fixture_portforward_remote_port": remote_forward_port,
    "artifacts": [test_log],
    "command": command_desc,
}

path = Path(metadata_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

fixture_reachable() {
  python3 - "$1" "$2" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
with socket.create_connection((host, port), timeout=3):
    pass
PY
}

derive_port_offset() {
  python3 - "${FIXTURE_RUN_ID}" <<'PY'
import sys
run_id = sys.argv[1]
print(sum(ord(ch) for ch in run_id) % 500)
PY
}

ensure_report
require_command xcodebuild
require_command python3

export FIXTURE_RUN_ID="${FIXTURE_RUN_ID:-lane-${LANE_NAME}-$(date -u +%Y%m%d%H%M%S)}"
export FIXTURE_SSH_PORT="${FIXTURE_SSH_PORT:-$(fixture_ssh_port)}"
export FIXTURE_MOSH_PORT="${FIXTURE_MOSH_PORT:-$(fixture_mosh_port)}"
export FIXTURE_REMOTE_ROOT="${FIXTURE_REMOTE_ROOT:-~/fps/${FIXTURE_RUN_ID}}"
export FIXTURE_DEVICE_HOST="${FIXTURE_DEVICE_HOST:-$(fixture_device_host)}"

port_offset="$(derive_port_offset)"
export FIXTURE_PORTFORWARD_LOCAL_PORT="${FIXTURE_PORTFORWARD_LOCAL_PORT:-$((18080 + port_offset))}"
export FIXTURE_PORTFORWARD_REMOTE_PORT="${FIXTURE_PORTFORWARD_REMOTE_PORT:-$((19080 + port_offset))}"
export FIXTURE_PORTFORWARD_TARGET_HOST="${FIXTURE_PORTFORWARD_TARGET_HOST:-localhost}"
export FIXTURE_PORTFORWARD_TARGET_PORT="${FIXTURE_PORTFORWARD_TARGET_PORT:-${FIXTURE_SSH_PORT}}"
export FIXTURE_REVERSE_TARGET_HOST="${FIXTURE_REVERSE_TARGET_HOST:-127.0.0.1}"

export BLINK_TEST_HOST="${BLINK_TEST_HOST:-${FIXTURE_SIM_HOST:-localhost}}"
export BLINK_TEST_PORT="${BLINK_TEST_PORT:-${FIXTURE_SSH_PORT}}"

simulator_id="${LANE_SIMULATOR_ID:-${SIMULATOR_ID:-}}"
if [[ -z "${simulator_id}" ]]; then
  simulator_id="$(resolve_simulator_id)" || fail "Unable to resolve simulator destination for ${LANE_NAME}"
fi

if ! fixture_reachable "${BLINK_TEST_HOST}" "${FIXTURE_SSH_PORT}"; then
  finish_epoch="$(epoch_now)"
  if [[ "${allow_no_fixture}" -eq 1 || "${ci_mode}" -eq 1 ]]; then
    write_metadata \
      "skip_reduced_coverage" \
      "Fixture unreachable at ${BLINK_TEST_HOST}:${FIXTURE_SSH_PORT}; lane skipped with reduced coverage." \
      "${start_epoch}" \
      "${finish_epoch}" \
      "${simulator_id}" \
      "${BLINK_TEST_HOST}" \
      "${FIXTURE_SSH_PORT}"
    exit 0
  fi

  write_metadata \
    "fail" \
    "Fixture unreachable at ${BLINK_TEST_HOST}:${FIXTURE_SSH_PORT}." \
    "${start_epoch}" \
    "${finish_epoch}" \
    "${simulator_id}" \
    "${BLINK_TEST_HOST}" \
    "${FIXTURE_SSH_PORT}"
  fail "Fixture unreachable at ${BLINK_TEST_HOST}:${FIXTURE_SSH_PORT}"
fi

status="pass"
notes="Port-forward lane passed using fixture ${BLINK_TEST_HOST}:${FIXTURE_SSH_PORT}."

if ! run_logged "${TEST_LOG}" \
  xcodebuild \
  -project "${REPO_ROOT}/Blink.xcodeproj" \
  -scheme BlinkQA \
  -configuration Debug \
  -destination "id=${simulator_id}" \
  -only-testing:SSHTests/SSHPortForwardTests/testForwardPort \
  -only-testing:SSHTests/SSHPortForwardTests/testListenerPort \
  -only-testing:SSHTests/SSHPortForwardTests/testReverseForwardPort \
  -only-testing:SSHTests/SSHPortForwardTests/testProxyCommand \
  -only-testing:SSHTests/SSHPortForwardTests/testProxyCommandConnFailure \
  test; then
  status="fail"
  notes="Port-forward lane failed. See ${TEST_LOG}."
fi

finish_epoch="$(epoch_now)"
write_metadata \
  "${status}" \
  "${notes}" \
  "${start_epoch}" \
  "${finish_epoch}" \
  "${simulator_id}" \
  "${BLINK_TEST_HOST}" \
  "${FIXTURE_SSH_PORT}"

[[ "${status}" == "pass" ]]
