#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

ensure_report

readonly LANE_NAME="g1_compile_device_generic"
readonly GATE_NAME="G1 Compile"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-device_generic_build}"
readonly WORKER_NAME="${WORKER_NAME:-gpt_5_3_codex__compile_sharding}"
readonly GATE_DIR="$(artifact_dir "g1-compile-device-generic")"
readonly DERIVED_DATA_DIR="${BLINK_COMPLETION_LOOP_DIR}/DerivedData-device-generic"
readonly METADATA_FILE="${LANE_METADATA_FILE:-${GATE_DIR}/lane-metadata.json}"
readonly OUTPUTS_FILE="${LANE_OUTPUTS_FILE:-${GATE_DIR}/lane-outputs.env}"
readonly COMMAND_NAME="xcodebuild -scheme Blink -destination generic/platform=iOS build"

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
  local duration
  duration="$(duration_since_start)"

  python3 - "${METADATA_FILE}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${COMMAND_NAME}" "${duration}" "${notes}" "${artifacts}" "${RESOURCE_GROUP}" "${WORKER_NAME}" "${coverage_mode}" "${DERIVED_DATA_DIR}" <<'PY'
import json
from pathlib import Path
import sys

(
  metadata_file,
  lane_name,
  gate_name,
  status,
  command_name,
  duration,
  notes,
  artifacts,
  resource_group,
  worker_name,
  coverage_mode,
  derived_data_dir,
) = sys.argv[1:]

payload = {
  "lane": lane_name,
  "gate": gate_name,
  "status": status,
  "command": command_name,
  "duration_sec": float(duration),
  "notes": notes,
  "artifacts": [item for item in artifacts.split(",") if item],
  "resource_group": resource_group,
  "worker": worker_name,
  "coverage_mode": coverage_mode,
  "requires_fixture": False,
  "requires_device": False,
  "outputs": {
    "derived_data": derived_data_dir,
    "destination": "generic/platform=iOS",
    "scheme": "Blink",
  },
}
path = Path(metadata_file)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

require_command xcodebuild
require_command python3

log "Running lane ${LANE_NAME}"
if ! run_logged "${GATE_DIR}/device-build.log" \
  xcodebuild \
  -project "${REPO_ROOT}/Blink.xcodeproj" \
  -scheme Blink \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  CODE_SIGNING_ALLOWED=NO \
  build; then
  write_metadata \
    "fail" \
    "Blink generic iOS device build failed." \
    "full" \
    "${GATE_DIR}/device-build.log"
  fail "Lane ${LANE_NAME} failed"
fi

cat > "${OUTPUTS_FILE}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
DERIVED_DATA_PATH=${DERIVED_DATA_DIR}
DESTINATION=generic/platform=iOS
SCHEME=Blink
COVERAGE_MODE=full
EOF

write_metadata \
  "pass" \
  "Built Blink for generic iOS destination with isolated derived-data root." \
  "full" \
  "${GATE_DIR}/device-build.log,${OUTPUTS_FILE}"

log "Lane ${LANE_NAME} completed. Metadata: ${METADATA_FILE}"
