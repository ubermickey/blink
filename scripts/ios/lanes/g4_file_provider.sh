#!/bin/bash

set -euo pipefail

LANE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_SCRIPT_DIR="$(cd "${LANE_SCRIPT_DIR}/.." && pwd)"
source "${IOS_SCRIPT_DIR}/common.sh"

allow_no_fixture=0
for arg in "$@"; do
  case "${arg}" in
    --allow-no-fixture) allow_no_fixture=1 ;;
    *) fail "Unknown argument: ${arg}" ;;
  esac
done

readonly LANE_NAME="g4_file_provider"
readonly GATE_NAME="G4 Domain Gates"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-simulator_g4_file_provider}"
readonly WORKER_NAME="${WORKER_NAME:-gpt_5_3_codex__g4_file_provider}"
readonly COMMAND_DESC="xcodebuild -scheme BlinkQA test -only-testing:BlinkFileProviderTests/BlinkFileProviderTests"

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
  local metadata_path="$5"
  local simulator_id="$6"
  local derived_data_dir="$7"
  local fixture_log="$8"
  local seed_log="$9"
  local test_log="${10}"
  local coverage_mode="${11}"

  python3 - "${metadata_path}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${notes}" "${started}" "${finished}" "${RESOURCE_GROUP}" "${WORKER_NAME}" "${COMMAND_DESC}" "${simulator_id}" "${derived_data_dir}" "${fixture_log}" "${seed_log}" "${test_log}" "${coverage_mode}" "${FIXTURE_RUN_ID}" "${FIXTURE_SSH_PORT}" "${FIXTURE_REMOTE_ROOT}" "${FIXTURE_DEVICE_HOST}" <<'PY'
import json
from pathlib import Path
import sys

(
    metadata_path,
    lane_name,
    gate_name,
    status,
    notes,
    started,
    finished,
    resource_group,
    worker_name,
    command_desc,
    simulator_id,
    derived_data_dir,
    fixture_log,
    seed_log,
    test_log,
    coverage_mode,
    fixture_run_id,
    fixture_ssh_port,
    fixture_remote_root,
    fixture_device_host,
) = sys.argv[1:]

payload = {
    "lane": lane_name,
    "gate": gate_name,
    "status": status,
    "notes": notes,
    "started_epoch": float(started),
    "finished_epoch": float(finished),
    "duration_sec": float(finished) - float(started),
    "resource_group": resource_group,
    "worker": worker_name,
    "coverage_mode": coverage_mode,
    "requires_fixture": True,
    "requires_device": False,
    "command": command_desc,
    "artifacts": [item for item in [fixture_log, seed_log, test_log] if item],
    "outputs": {
        "simulator_id": simulator_id,
        "derived_data_dir": derived_data_dir,
        "fixture_run_id": fixture_run_id,
        "fixture_ssh_port": fixture_ssh_port,
        "fixture_remote_root": fixture_remote_root,
        "fixture_device_host": fixture_device_host,
    },
}

path = Path(metadata_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

write_outputs() {
  local path="$1"
  local simulator_id="$2"
  local derived_data_dir="$3"
  local coverage_mode="$4"
  cat > "${path}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
SIMULATOR_ID=${simulator_id}
DERIVED_DATA_DIR=${derived_data_dir}
FIXTURE_RUN_ID=${FIXTURE_RUN_ID}
FIXTURE_SSH_PORT=${FIXTURE_SSH_PORT}
FIXTURE_MOSH_PORT=${FIXTURE_MOSH_PORT}
FIXTURE_REMOTE_ROOT=${FIXTURE_REMOTE_ROOT}
FIXTURE_DEVICE_HOST=${FIXTURE_DEVICE_HOST}
COVERAGE_MODE=${coverage_mode}
EOF
}

configure_fixture_env() {
  local run_id_default
  run_id_default="${LANE_NAME}-$(date -u +%Y%m%dT%H%M%S)-$$"
  export FIXTURE_RUN_ID="${FIXTURE_RUN_ID:-${run_id_default}}"
  export FIXTURE_SSH_PORT="${FIXTURE_SSH_PORT:-$(fixture_ssh_port)}"
  export FIXTURE_MOSH_PORT="${FIXTURE_MOSH_PORT:-$(fixture_mosh_port)}"
  export FIXTURE_REMOTE_ROOT="${FIXTURE_REMOTE_ROOT:-~/fps/${FIXTURE_RUN_ID}}"
  export FIXTURE_DEVICE_HOST="${FIXTURE_DEVICE_HOST:-${FIXTURE_SIM_HOST:-localhost}}"
}

seed_fixture_root() {
  local seed_log="$1"
  local fixture_user="${FIXTURE_SSH_USER:-no-password}"

  run_logged "${seed_log}" \
    ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -p "${FIXTURE_SSH_PORT}" \
    "${fixture_user}@${FIXTURE_DEVICE_HOST}" \
    /bin/sh -s -- "${FIXTURE_REMOTE_ROOT}" <<'SH'
set -eu

remote_root="$1"
seed_root="${HOME}/fps"

case "${remote_root}" in
  "~")
    remote_root="${HOME}"
    ;;
  "~/"*)
    remote_root="${HOME}/${remote_root#~/}"
    ;;
esac

if [ "${remote_root}" = "${seed_root}" ]; then
  echo "FIXTURE_REMOTE_ROOT must not equal ${seed_root}; use an isolated per-lane root." >&2
  exit 2
fi

test -d "${seed_root}/fps"
test -d "${seed_root}/fps_changes"
test -d "${seed_root}/fps_symlinks"

rm -rf "${remote_root}"
mkdir -p "${remote_root}"
cp -R "${seed_root}/fps" "${remote_root}/"
cp -R "${seed_root}/fps_changes" "${remote_root}/"
cp -R "${seed_root}/fps_symlinks" "${remote_root}/"
SH
}

ensure_report
require_command xcodebuild
require_command python3
require_command ssh

readonly LANE_DIR="$(artifact_dir "g4-domain/${LANE_NAME}")"
readonly METADATA_PATH="${LANE_METADATA_FILE:-${LANE_DIR}/lane-metadata.json}"
readonly OUTPUTS_PATH="${LANE_OUTPUTS_FILE:-${LANE_DIR}/lane-outputs.env}"
readonly FIXTURE_LOG="${LANE_DIR}/fixture-up.log"
readonly SEED_LOG="${LANE_DIR}/fixture-seed.log"
readonly TEST_LOG="${LANE_DIR}/test.log"

simulator_id="${LANE_SIMULATOR_ID:-${SIMULATOR_ID:-}}"
if [[ -z "${simulator_id}" ]]; then
  simulator_id="$(resolve_simulator_id)" || fail "Unable to resolve simulator destination for ${LANE_NAME}"
fi

derived_data_dir="${LANE_DERIVED_DATA_DIR:-${BLINK_COMPLETION_LOOP_DIR}/DerivedData-${LANE_NAME}}"
ensure_dir "${derived_data_dir}"
configure_fixture_env

start_epoch="$(epoch_now)"
status="pass"
coverage_mode="full"
notes="File Provider lane completed with isolated fixture root ${FIXTURE_REMOTE_ROOT}."

if ! run_logged "${FIXTURE_LOG}" "${IOS_SCRIPT_DIR}/fixture-up"; then
  if [[ "${allow_no_fixture}" -eq 1 ]]; then
    status="skip_reduced_coverage"
    coverage_mode="reduced"
    notes="Fixture unavailable; File Provider lane skipped with reduced coverage."
    finish_epoch="$(epoch_now)"
    write_outputs "${OUTPUTS_PATH}" "${simulator_id}" "${derived_data_dir}" "${coverage_mode}"
    write_metadata "${status}" "${notes}" "${start_epoch}" "${finish_epoch}" "${METADATA_PATH}" "${simulator_id}" "${derived_data_dir}" "${FIXTURE_LOG}" "" "" "${coverage_mode}"
    exit 0
  fi
  status="fail"
  notes="Fixture startup failed. See ${FIXTURE_LOG}."
fi

if [[ "${status}" == "pass" ]] && ! seed_fixture_root "${SEED_LOG}"; then
  status="fail"
  notes="Fixture seeding failed for ${FIXTURE_REMOTE_ROOT}. See ${SEED_LOG}."
fi

if [[ "${status}" == "pass" ]] && ! run_logged "${TEST_LOG}" \
  xcodebuild \
  -project "${REPO_ROOT}/Blink.xcodeproj" \
  -scheme BlinkQA \
  -configuration Debug \
  -destination "id=${simulator_id}" \
  -derivedDataPath "${derived_data_dir}" \
  -only-testing:BlinkFileProviderTests/BlinkFileProviderTests \
  test; then
  status="fail"
  notes="File Provider test lane failed. See ${TEST_LOG}."
fi

finish_epoch="$(epoch_now)"
write_outputs "${OUTPUTS_PATH}" "${simulator_id}" "${derived_data_dir}" "${coverage_mode}"
write_metadata "${status}" "${notes}" "${start_epoch}" "${finish_epoch}" "${METADATA_PATH}" "${simulator_id}" "${derived_data_dir}" "${FIXTURE_LOG}" "${SEED_LOG}" "${TEST_LOG}" "${coverage_mode}"

[[ "${status}" == "pass" ]]
