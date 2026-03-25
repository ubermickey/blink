#!/bin/bash

set -euo pipefail

LANE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_SCRIPT_DIR="$(cd "${LANE_SCRIPT_DIR}/.." && pwd)"
source "${IOS_SCRIPT_DIR}/common.sh"

readonly LANE_NAME="g4_blinkcode"
readonly GATE_NAME="G4 Domain Gates"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-simulator_g4_blinkcode}"
readonly WORKER="${LANE_WORKER:-gpt_5_3_codex__g4_blinkcode}"
readonly COVERAGE_MODE="${COVERAGE_MODE:-full}"
readonly REQUIRES_FIXTURE="${REQUIRES_FIXTURE:-false}"
readonly REQUIRES_DEVICE="${REQUIRES_DEVICE:-false}"
readonly COMMAND_DESC="xcodebuild test-without-building (BlinkCodeTests)"

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
  local xctestrun_path="$8"
  local build_log="$9"
  local test_log="${10}"
  local outputs_file="${11}"
  python3 - "${metadata_path}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${WORKER}" "${RESOURCE_GROUP}" "${COVERAGE_MODE}" "${notes}" "${started}" "${finished}" "${simulator_id}" "${derived_data_dir}" "${xctestrun_path}" "${build_log}" "${test_log}" "${outputs_file}" "${COMMAND_DESC}" "${REQUIRES_FIXTURE}" "${REQUIRES_DEVICE}" <<'PY'
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
    derived_data_dir,
    xctestrun_path,
    build_log,
    test_log,
    outputs_file,
    command_desc,
    requires_fixture,
    requires_device,
) = sys.argv[1:]

def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}

payload = {
    "lane": lane,
    "gate": gate,
    "status": status,
    "worker": worker,
    "resource_group": resource_group,
    "coverage_mode": coverage_mode,
    "requires_fixture": parse_bool(requires_fixture),
    "requires_device": parse_bool(requires_device),
    "notes": notes,
    "started_epoch": float(started),
    "finished_epoch": float(finished),
    "duration_sec": float(finished) - float(started),
    "command": command_desc,
    "outputs": {
      "simulator_id": simulator_id,
      "derived_data_dir": derived_data_dir,
      "xctestrun_path": xctestrun_path,
    },
    "artifacts": [item for item in [build_log, test_log, outputs_file] if item],
}

path = Path(metadata_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

find_xctestrun() {
  local derived_data_dir="$1"
  local products_dir="${derived_data_dir}/Build/Products"
  if [[ ! -d "${products_dir}" ]]; then
    return 0
  fi
  find "${products_dir}" -maxdepth 1 -type f -name "*.xctestrun" 2>/dev/null | sort | head -n 1
}

pick_xctestrun_candidate() {
  local candidate
  if [[ -n "${LANE_XCTESTRUN_PATH:-}" && -f "${LANE_XCTESTRUN_PATH}" ]]; then
    printf '%s\n' "${LANE_XCTESTRUN_PATH}"
    return 0
  fi

  for candidate in \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData-g2_code_snippets" \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData-sim" \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData"; do
    candidate="$(find_xctestrun "${candidate}")"
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
}

ensure_build_for_testing() {
  local simulator_id="$1"
  local derived_data_dir="$2"
  local build_log="$3"
  local xctestrun_path

  xctestrun_path="$(pick_xctestrun_candidate)"
  if [[ -n "${xctestrun_path}" && "${FORCE_BUILD_FOR_TESTING:-0}" -eq 0 ]]; then
    printf '%s\n' "${xctestrun_path}"
    return 0
  fi

  if ! run_logged "${build_log}" \
    xcodebuild \
    -project "${REPO_ROOT}/Blink.xcodeproj" \
    -scheme BlinkQA \
    -configuration Debug \
    -destination "id=${simulator_id}" \
    -derivedDataPath "${derived_data_dir}" \
    build-for-testing; then
    return 1
  fi

  xctestrun_path="$(find_xctestrun "${derived_data_dir}")"
  [[ -n "${xctestrun_path}" ]] || return 1
  printf '%s\n' "${xctestrun_path}"
}

ensure_report
require_command xcodebuild
require_command python3

readonly LANE_DIR="$(artifact_dir "g4-domain/${LANE_NAME}")"
readonly METADATA_PATH="${LANE_DIR}/lane-metadata.json"
readonly OUTPUTS_FILE="${LANE_DIR}/lane-outputs.env"
readonly BUILD_LOG="${LANE_DIR}/build-for-testing.log"
readonly TEST_LOG="${LANE_DIR}/blinkcode-test.log"

start_epoch="$(epoch_now)"
status="pass"
notes="BlinkCode lane completed with BlinkCodeTests."
simulator_id=""
derived_data_dir="${LANE_DERIVED_DATA_DIR:-${BLINK_COMPLETION_LOOP_DIR}/DerivedData-${LANE_NAME}}"
xctestrun_path=""

simulator_id="${LANE_SIMULATOR_ID:-${SIMULATOR_ID:-}}"
if [[ -z "${simulator_id}" ]]; then
  if ! simulator_id="$(resolve_simulator_id)"; then
    status="fail"
    notes="Unable to resolve simulator destination for ${LANE_NAME}."
  fi
fi

if [[ "${status}" == "pass" ]]; then
  ensure_dir "${derived_data_dir}"
fi

if [[ "${status}" == "pass" ]]; then
  if ! xctestrun_path="$(ensure_build_for_testing "${simulator_id}" "${derived_data_dir}" "${BUILD_LOG}")"; then
    status="fail"
    notes="build-for-testing failed for BlinkCode lane. See ${BUILD_LOG}."
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! run_logged "${TEST_LOG}" \
    xcodebuild \
    test-without-building \
    -xctestrun "${xctestrun_path}" \
    -destination "id=${simulator_id}" \
    -derivedDataPath "${derived_data_dir}" \
    -only-testing:BlinkCodeTests; then
    status="fail"
    notes="BlinkCodeTests failed. See ${TEST_LOG}."
  fi
fi

cat > "${OUTPUTS_FILE}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
STATUS=${status}
SIMULATOR_ID=${simulator_id}
DERIVED_DATA_PATH=${derived_data_dir}
XCTESTRUN_PATH=${xctestrun_path}
COVERAGE_MODE=${COVERAGE_MODE}
EOF

finish_epoch="$(epoch_now)"
write_metadata "${status}" "${notes}" "${start_epoch}" "${finish_epoch}" "${METADATA_PATH}" "${simulator_id}" "${derived_data_dir}" "${xctestrun_path}" "${BUILD_LOG}" "${TEST_LOG}" "${OUTPUTS_FILE}"

[[ "${status}" == "pass" ]]
