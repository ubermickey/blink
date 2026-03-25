#!/bin/bash

set -euo pipefail

LANE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_SCRIPT_DIR="$(cd "${LANE_SCRIPT_DIR}/.." && pwd)"
source "${IOS_SCRIPT_DIR}/common.sh"

readonly LANE_NAME="g4_free_build_runtime"
readonly GATE_NAME="G4 Domain Gates"
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-simulator_g4_free_build_runtime}"
readonly WORKER="${LANE_WORKER:-gpt_5_3_codex__g4_blinkcode}"
readonly REQUIRES_FIXTURE="${REQUIRES_FIXTURE:-false}"
readonly REQUIRES_DEVICE="${REQUIRES_DEVICE:-false}"
readonly COMMAND_DESC="free-build contract checks + simulator launch smoke"

ALLOW_REDUCED_COVERAGE="${ALLOW_REDUCED_COVERAGE:-0}"

epoch_now() {
  python3 - <<'PY'
import time
print(time.time())
PY
}

bool_is_true() {
  [[ "$1" == "1" || "$1" == "true" || "$1" == "yes" || "$1" == "on" ]]
}

write_metadata() {
  local status="$1"
  local notes="$2"
  local coverage_mode="$3"
  local started="$4"
  local finished="$5"
  local metadata_path="$6"
  local simulator_id="$7"
  local derived_data_dir="$8"
  local app_path="$9"
  local outputs_file="${10}"
  local build_settings_log="${11}"
  local validation_log="${12}"
  local sim_build_log="${13}"
  local sim_install_log="${14}"
  local sim_launch_log="${15}"
  python3 - "${metadata_path}" "${LANE_NAME}" "${GATE_NAME}" "${status}" "${WORKER}" "${RESOURCE_GROUP}" "${coverage_mode}" "${notes}" "${started}" "${finished}" "${simulator_id}" "${derived_data_dir}" "${app_path}" "${outputs_file}" "${build_settings_log}" "${validation_log}" "${sim_build_log}" "${sim_install_log}" "${sim_launch_log}" "${COMMAND_DESC}" "${REQUIRES_FIXTURE}" "${REQUIRES_DEVICE}" <<'PY'
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
    app_path,
    outputs_file,
    build_settings_log,
    validation_log,
    sim_build_log,
    sim_install_log,
    sim_launch_log,
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
      "app_path": app_path,
    },
    "artifacts": [
      item for item in [
        build_settings_log,
        validation_log,
        sim_build_log,
        sim_install_log,
        sim_launch_log,
        outputs_file,
      ] if item
    ],
}

path = Path(metadata_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
}

pick_simulator_app() {
  local candidate
  if [[ -n "${LANE_APP_PATH:-}" && -d "${LANE_APP_PATH}" ]]; then
    printf '%s\n' "${LANE_APP_PATH}"
    return 0
  fi
  for candidate in \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData-sim/Build/Products/Debug-iphonesimulator/Blink.app" \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData-g2_code_snippets/Build/Products/Debug-iphonesimulator/Blink.app" \
    "${BLINK_COMPLETION_LOOP_DIR}/DerivedData/Build/Products/Debug-iphonesimulator/Blink.app"; do
    if [[ -d "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
}

ensure_report
require_command xcodebuild
require_command python3
require_command xcrun
require_command rg

readonly LANE_DIR="$(artifact_dir "g4-domain/${LANE_NAME}")"
readonly METADATA_PATH="${LANE_DIR}/lane-metadata.json"
readonly OUTPUTS_FILE="${LANE_DIR}/lane-outputs.env"
readonly BUILD_SETTINGS_LOG="${LANE_DIR}/build-settings.log"
readonly VALIDATION_LOG="${LANE_DIR}/validations.log"
readonly SIM_BUILD_LOG="${LANE_DIR}/sim-build.log"
readonly SIM_INSTALL_LOG="${LANE_DIR}/sim-install.log"
readonly SIM_LAUNCH_LOG="${LANE_DIR}/sim-launch.log"

start_epoch="$(epoch_now)"
status="pass"
coverage_mode="full"
notes="Free-build compile/runtime contract verified."
simulator_id=""
derived_data_dir="${LANE_DERIVED_DATA_DIR:-${BLINK_COMPLETION_LOOP_DIR}/DerivedData-${LANE_NAME}}"
app_path=""
bundle=""

{
  echo "Validation started at $(timestamp_utc)"
  echo "Lane=${LANE_NAME}"
} > "${VALIDATION_LOG}"

simulator_id="${LANE_SIMULATOR_ID:-${SIMULATOR_ID:-}}"
if [[ -z "${simulator_id}" ]]; then
  if ! simulator_id="$(resolve_simulator_id)"; then
    status="fail"
    notes="Unable to resolve simulator destination for ${LANE_NAME}."
    echo "FAIL: could not resolve simulator destination" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! run_logged "${BUILD_SETTINGS_LOG}" \
    xcodebuild \
    -project "${REPO_ROOT}/Blink.xcodeproj" \
    -scheme Blink \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -showBuildSettings; then
    status="fail"
    notes="Unable to read Blink Debug build settings."
    echo "FAIL: xcodebuild -showBuildSettings failed" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! rg -q "SWIFT_ACTIVE_COMPILATION_CONDITIONS = .*BLINK_FREE_BUILD" "${BUILD_SETTINGS_LOG}"; then
    status="fail"
    notes="Debug build settings do not include BLINK_FREE_BUILD."
    echo "FAIL: BLINK_FREE_BUILD missing from xcodebuild settings" >> "${VALIDATION_LOG}"
  else
    echo "PASS: BLINK_FREE_BUILD present in xcodebuild settings" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! rg -q "SWIFT_ACTIVE_COMPILATION_CONDITIONS\\[config=Debug\\].*BLINK_FREE_BUILD" "${REPO_ROOT}/developer_setup.xcconfig"; then
    status="fail"
    notes="developer_setup.xcconfig Debug conditions do not include BLINK_FREE_BUILD."
    echo "FAIL: BLINK_FREE_BUILD missing from developer_setup.xcconfig" >> "${VALIDATION_LOG}"
  else
    echo "PASS: BLINK_FREE_BUILD present in developer_setup.xcconfig" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! rg -q "^#if BLINK_FREE_BUILD" "${REPO_ROOT}/Blink/Subscriptions/FreeAccountStubs.swift"; then
    status="fail"
    notes="FreeAccountStubs.swift is not guarded for BLINK_FREE_BUILD."
    echo "FAIL: missing #if BLINK_FREE_BUILD in FreeAccountStubs.swift" >> "${VALIDATION_LOG}"
  elif ! rg -q 'Free \\(Sideloaded\\)' "${REPO_ROOT}/Blink/Subscriptions/FreeAccountStubs.swift"; then
    status="fail"
    notes="FreeAccountStubs.swift does not expose expected free-build stub marker."
    echo "FAIL: missing Free (Sideloaded) stub marker" >> "${VALIDATION_LOG}"
  else
    echo "PASS: FreeAccountStubs.swift free-build guard and stub values present" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  if ! rg -q '#if !BLINK_FREE_BUILD' "${REPO_ROOT}/Blink/SceneDelegate.swift"; then
    status="fail"
    notes="SceneDelegate.swift does not guard RevenueCat import in free build."
    echo "FAIL: missing !BLINK_FREE_BUILD guard in SceneDelegate.swift" >> "${VALIDATION_LOG}"
  elif ! rg -q 'let revCatId = "free-build"' "${REPO_ROOT}/Blink/BuildApi.swift"; then
    status="fail"
    notes="BuildApi.swift missing free-build backend identity stub."
    echo "FAIL: missing free-build rev_cat_user_id identity in BuildApi.swift" >> "${VALIDATION_LOG}"
  else
    echo "PASS: RevenueCat guard and free-build backend identity checks passed" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  app_path="$(pick_simulator_app || true)"
  if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
    ensure_dir "${derived_data_dir}"
    if ! run_logged "${SIM_BUILD_LOG}" \
      xcodebuild \
      -project "${REPO_ROOT}/Blink.xcodeproj" \
      -scheme Blink \
      -configuration Debug \
      -destination "id=${simulator_id}" \
      -derivedDataPath "${derived_data_dir}" \
      build; then
      status="fail"
      notes="Simulator build failed for free-build runtime lane."
      echo "FAIL: simulator build failed" >> "${VALIDATION_LOG}"
    else
      app_path="${derived_data_dir}/Build/Products/Debug-iphonesimulator/Blink.app"
    fi
  fi
fi

if [[ "${status}" == "pass" && ! -d "${app_path}" ]]; then
  status="fail"
  notes="Blink.app missing after simulator build."
  echo "FAIL: built app not found at ${app_path}" >> "${VALIDATION_LOG}"
fi

if [[ "${status}" == "pass" ]]; then
  if ! run_logged "${SIM_INSTALL_LOG}" xcrun simctl install "${simulator_id}" "${app_path}"; then
    status="fail"
    notes="Failed to install Blink on simulator ${simulator_id}."
    echo "FAIL: simctl install failed" >> "${VALIDATION_LOG}"
  fi
fi

if [[ "${status}" == "pass" ]]; then
  bundle="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${app_path}/Info.plist" 2>/dev/null || true)"
  if [[ -z "${bundle}" ]]; then
    bundle="$(bundle_id)"
  fi

  if ! run_logged "${SIM_LAUNCH_LOG}" xcrun simctl launch "${simulator_id}" "${bundle}"; then
    if bool_is_true "${ALLOW_REDUCED_COVERAGE}"; then
      status="skip_reduced_coverage"
      coverage_mode="reduced"
      notes="Free-build runtime launch skipped with reduced coverage due to simulator launch failure."
      echo "SKIP_REDUCED_COVERAGE: simctl launch failed but reduced coverage allowed" >> "${VALIDATION_LOG}"
    else
      status="fail"
      notes="Blink free-build failed to launch in simulator."
      echo "FAIL: simctl launch failed" >> "${VALIDATION_LOG}"
    fi
  else
    echo "PASS: simctl launch succeeded for bundle ${bundle}" >> "${VALIDATION_LOG}"
    sleep 2
    xcrun simctl terminate "${simulator_id}" "${bundle}" >/dev/null 2>&1 || true
  fi
fi

cat > "${OUTPUTS_FILE}" <<EOF
LANE=${LANE_NAME}
GATE=${GATE_NAME}
STATUS=${status}
COVERAGE_MODE=${coverage_mode}
SIMULATOR_ID=${simulator_id}
DERIVED_DATA_PATH=${derived_data_dir}
APP_PATH=${app_path}
ALLOW_REDUCED_COVERAGE=${ALLOW_REDUCED_COVERAGE}
EOF

finish_epoch="$(epoch_now)"
write_metadata "${status}" "${notes}" "${coverage_mode}" "${start_epoch}" "${finish_epoch}" "${METADATA_PATH}" "${simulator_id}" "${derived_data_dir}" "${app_path}" "${OUTPUTS_FILE}" "${BUILD_SETTINGS_LOG}" "${VALIDATION_LOG}" "${SIM_BUILD_LOG}" "${SIM_INSTALL_LOG}" "${SIM_LAUNCH_LOG}"

[[ "${status}" == "pass" || "${status}" == "skip_reduced_coverage" ]]
