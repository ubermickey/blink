#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_fixture=0
allow_no_fixture=0
ci_mode=0

for arg in "$@"; do
  case "${arg}" in
    --check-fixture) check_fixture=1 ;;
    --allow-no-fixture) allow_no_fixture=1 ;;
    --ci) ci_mode=1 ;;
    *) fail "Unknown argument: ${arg}" ;;
  esac
done

ensure_report

readonly LANE_NAME="g0_toolchain"
readonly GATE_NAME="G0 Toolchain"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-host}"
readonly WORKER_NAME="${WORKER_NAME:-gpt_5_3_codex__compile_sharding}"
readonly GATE_DIR="$(artifact_dir "g0-toolchain")"
readonly METADATA_FILE="${LANE_METADATA_FILE:-${GATE_DIR}/lane-metadata.json}"
readonly OUTPUTS_FILE="${LANE_OUTPUTS_FILE:-${GATE_DIR}/lane-outputs.env}"
readonly COMMAND_NAME="scripts/ios/lanes/g0_toolchain.sh"

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
  local requires_fixture="$4"
  local requires_device="$5"
  local artifacts="$6"
  local simulator_id="$7"
  local fixture_status="$8"
  local skip_list="$9"
  local duration
  duration="$(duration_since_start)"

  python3 - "${METADATA_FILE}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${COMMAND_NAME}" "${duration}" "${notes}" "${artifacts}" "${RESOURCE_GROUP}" "${WORKER_NAME}" "${coverage_mode}" "${requires_fixture}" "${requires_device}" "${simulator_id}" "${fixture_status}" "${skip_list}" <<'PY'
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
  requires_fixture,
  requires_device,
  simulator_id,
  fixture_status,
  skip_list,
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
  "requires_fixture": requires_fixture.lower() in ("true", "1", "yes"),
  "requires_device": requires_device.lower() in ("true", "1", "yes"),
  "outputs": {
    "simulator_id": simulator_id,
    "fixture_status": fixture_status,
    "skip_tests": [item for item in skip_list.split(",") if item],
  },
}
path = Path(metadata_file)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\\n")
PY
}

require_command xcodebuild
require_command python3

team="$(team_id)"
[[ -n "${team}" ]] || fail "TEAM_ID is not configured in developer_setup.xcconfig"
bundle="$(bundle_id)"
[[ -n "${bundle}" ]] || fail "BUNDLE_ID is not configured in developer_setup.xcconfig"
[[ -d "${REPO_ROOT}/Frameworks" ]] || fail "Frameworks directory is missing"
[[ -d "${REPO_ROOT}/Resources" ]] || fail "Resources directory is missing"
[[ -f "${REPO_ROOT}/BlinkQA.xctestplan" ]] || fail "BlinkQA.xctestplan is missing"
[[ -f "${REPO_ROOT}/Blink.xcodeproj/xcshareddata/xcschemes/BlinkQA.xcscheme" ]] || fail "BlinkQA.xcscheme is missing"

simulator_id="${SIMULATOR_ID:-}"
if [[ -z "${simulator_id}" ]]; then
  simulator_id="$(resolve_simulator_id)" || fail "Unable to resolve an iOS simulator destination."
fi

export FIXTURE_RUN_ID="${FIXTURE_RUN_ID:-lane-${LANE_NAME}-$(date -u +%Y%m%d%H%M%S)}"
export FIXTURE_SSH_PORT="${FIXTURE_SSH_PORT:-$(fixture_ssh_port)}"
export FIXTURE_MOSH_PORT="${FIXTURE_MOSH_PORT:-$(fixture_mosh_port)}"
export FIXTURE_REMOTE_ROOT="${FIXTURE_REMOTE_ROOT:-~/fps/${FIXTURE_RUN_ID}}"
export FIXTURE_DEVICE_HOST="${FIXTURE_DEVICE_HOST:-$(fixture_device_host)}"

fixture_status="not_checked"
coverage_mode="full"
skip_tests=""
notes="Validated TEAM_ID, BUNDLE_ID, BlinkQA assets, simulator destination ${simulator_id}."

if [[ "${check_fixture}" -eq 1 ]]; then
  if "${SCRIPT_DIR}/../fixture-up" >/dev/null 2>&1; then
    fixture_status="available"
    notes="${notes} Fixture available."
  elif [[ "${allow_no_fixture}" -eq 1 || "${ci_mode}" -eq 1 ]]; then
    fixture_status="unavailable"
    coverage_mode="reduced"
    skip_tests="-skip-testing:SSHTests,-skip-testing:BlinkFileProviderTests,-skip-testing:BlinkTests/MoshBootstrapTests,-skip-testing:BlinkTests/SEKeyTests"
    notes="${notes} Fixture unavailable; downstream lanes should use reduced coverage."
  else
    write_metadata \
      "fail" \
      "Fixture startup failed and reduced coverage is not allowed." \
      "full" \
      "true" \
      "false" \
      "${GATE_DIR}" \
      "${simulator_id}" \
      "failed" \
      ""
    fail "Fixture startup failed. Re-run with --allow-no-fixture only if reduced coverage is intended."
  fi
fi

cat > "${OUTPUTS_FILE}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
SIMULATOR_ID=${simulator_id}
FIXTURE_STATUS=${fixture_status}
FIXTURE_RUN_ID=${FIXTURE_RUN_ID}
FIXTURE_SSH_PORT=${FIXTURE_SSH_PORT}
FIXTURE_MOSH_PORT=${FIXTURE_MOSH_PORT}
FIXTURE_REMOTE_ROOT=${FIXTURE_REMOTE_ROOT}
FIXTURE_DEVICE_HOST=${FIXTURE_DEVICE_HOST}
SKIP_TEST_ARGS=${skip_tests}
COVERAGE_MODE=${coverage_mode}
EOF

write_metadata \
  "pass" \
  "${notes}" \
  "${coverage_mode}" \
  "${check_fixture}" \
  "false" \
  "${GATE_DIR},${OUTPUTS_FILE}" \
  "${simulator_id}" \
  "${fixture_status}" \
  "${skip_tests}"

log "Lane ${LANE_NAME} completed. Metadata: ${METADATA_FILE}"
