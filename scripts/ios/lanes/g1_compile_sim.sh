#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

ensure_report

readonly LANE_NAME="g1_compile_sim"
readonly GATE_NAME="G1 Compile"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-simulator_build}"
readonly WORKER_NAME="${WORKER_NAME:-gpt_5_3_codex__compile_sharding}"
readonly GATE_DIR="$(artifact_dir "g1-compile-sim")"
readonly DERIVED_DATA_DIR="${BLINK_COMPLETION_LOOP_DIR}/DerivedData-sim"
readonly METADATA_FILE="${LANE_METADATA_FILE:-${GATE_DIR}/lane-metadata.json}"
readonly OUTPUTS_FILE="${LANE_OUTPUTS_FILE:-${GATE_DIR}/lane-outputs.env}"
readonly COMMAND_NAME="xcodebuild -scheme BlinkQA build-for-testing"

start_epoch="$(python3 - <<'PY'
import time
print(time.time())
PY
)"

duration_since_start() {
  python3 - "${start_epoch}" <<'PY'
import sys
import time
print(f"{time.time() - float(sys.argv[1]):.2f}")
PY
}

write_metadata() {
  local status="$1"
  local notes="$2"
  local coverage_mode="$3"
  local artifacts="$4"
  local simulator_id="$5"
  local duration
  duration="$(duration_since_start)"

  python3 - "${METADATA_FILE}" <<PY
import json
from pathlib import Path

payload = {
  "lane": "${LANE_NAME}",
  "gate": "${GATE_NAME}",
  "status": "${status}",
  "command": "${COMMAND_NAME}",
  "duration_sec": float("${duration}"),
  "notes": "${notes}",
  "artifacts": [item for item in "${artifacts}".split(",") if item],
  "resource_group": "${RESOURCE_GROUP}",
  "worker": "${WORKER_NAME}",
  "coverage_mode": "${coverage_mode}",
  "requires_fixture": False,
  "requires_device": False,
  "outputs": {
    "simulator_id": "${simulator_id}",
    "derived_data": "${DERIVED_DATA_DIR}",
  },
}
path = Path("${METADATA_FILE}")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\\n")
PY
}

require_command xcodebuild
require_command python3

find_xctestrun() {
  local derived_data_dir="$1"
  local products_dir="${derived_data_dir}/Build/Products"
  if [[ ! -d "${products_dir}" ]]; then
    return 0
  fi
  find "${products_dir}" -maxdepth 1 -type f -name "*.xctestrun" 2>/dev/null | sort | head -n 1
}

simulator_id="${SIMULATOR_ID:-}"
if [[ -z "${simulator_id}" ]]; then
  simulator_id="$(resolve_simulator_id)" || fail "Unable to resolve an iOS simulator destination."
fi

log "Running lane ${LANE_NAME} on simulator ${simulator_id}"
if ! run_logged "${GATE_DIR}/build-for-testing.log" \
  xcodebuild \
  -project "${REPO_ROOT}/Blink.xcodeproj" \
  -scheme BlinkQA \
  -configuration Debug \
  -destination "id=${simulator_id}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build-for-testing; then
  write_metadata \
    "fail" \
    "BlinkQA build-for-testing failed on simulator ${simulator_id}." \
    "full" \
    "${GATE_DIR}/build-for-testing.log" \
    "${simulator_id}"
  fail "Lane ${LANE_NAME} failed"
fi

xctestrun_path="$(find_xctestrun "${DERIVED_DATA_DIR}")"
[[ -n "${xctestrun_path}" ]] || fail "Unable to locate .xctestrun in ${DERIVED_DATA_DIR}"

cat > "${OUTPUTS_FILE}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
SIMULATOR_ID=${simulator_id}
DERIVED_DATA_PATH=${DERIVED_DATA_DIR}
XCTESTRUN_PATH=${xctestrun_path}
COVERAGE_MODE=full
EOF

write_metadata \
  "pass" \
  "Built BlinkQA for simulator testing using an isolated derived-data root." \
  "full" \
  "${GATE_DIR}/build-for-testing.log,${OUTPUTS_FILE}" \
  "${simulator_id}"

log "Lane ${LANE_NAME} completed. Metadata: ${METADATA_FILE}"
