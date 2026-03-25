# Blink iOS Testing Loop (v5)

This branch is moving to a lane-based v5 loop centered on `scripts/ios/lanes.json`.
The lane contract exists now; full conductor execution is still in progress.

## Current Operator Flow

Use the existing top-level entrypoints:

```bash
./scripts/ios/baseline-sync
./scripts/ios/fixture-up
./scripts/ios/verify-fast
./scripts/ios/deploy-device
./scripts/ios/verify-full
./scripts/ios/acceptance
```

Current behavior:
- `verify-fast` is still a monolithic wrapper for `G0 + G1 + G2`.
- `verify-full` currently runs `verify-fast`, then `deploy-device`, then records `G4` as `pending_manual`.
- `acceptance` stages the manual checklist and records `G8` as `pending_manual`.

## Lane Model (Source Of Truth)

`scripts/ios/lanes.json` defines:
- lane id, gate, command
- dependencies (`depends_on`)
- lock domain (`resource_group`)
- fixture/device requirements
- artifact directory and coverage mode
- worker ownership label

The configured mode sets are:
- `fast`: `prep_baseline`, `g0_toolchain`, `g1_compile_sim`, `g1_compile_device_generic`, `g2_core`
- `full`: `fast` lanes plus `g2_files`, `g2_code_snippets`, `g2_ui_smoke`, `g3_runtime_smoke`, `g4_*`, `g8_acceptance`, `g9_release`

Current implementation status:
- Implemented lane runners: `g0_toolchain`, `g1_compile_sim`, `g1_compile_device_generic`, `g2_core`, `g2_files`, `g2_code_snippets`, `g2_ui_smoke`, `g4_scp_sftp`, `g4_file_provider`, `g4_blinkcode`, `g4_free_build_runtime`
- Planned/pending orchestration wiring: `orchestrate-v5` entrypoint and lane manifest command hookups for several `g2/g4/g9` rows that are still marked `manual` in `lanes.json`

## Resource Groups And Parallelism Rules

Lane `resource_group` values are the lock keys for safe fan-out:
- `host`: non-exclusive host work
- `fixture`: fixture-backed work that must not collide on shared fixture state
- `device_ipad`: single hardware iPad lane at a time
- simulator shards: `simulator_build`, `simulator_core`, `simulator_files`, `simulator_code_snippets`, `simulator_ui_smoke`

Rule of thumb:
- lanes in different resource groups may run in parallel if dependencies are satisfied
- lanes in the same resource group should be serialized
- `device_ipad` is always serialized

## Fixture Contract And Reduced Coverage

Standard fixture env vars for lane runners:
- `FIXTURE_RUN_ID`
- `FIXTURE_SSH_PORT` (default `2222`)
- `FIXTURE_MOSH_PORT` (default `2223`)
- `FIXTURE_REMOTE_ROOT`
- `FIXTURE_DEVICE_HOST` (defaults to simulator host or `<LocalHostName>.local` depending on lane wrapper)

Build/signing contract:
- `TEAM_ID` and `BUNDLE_ID` are read from `developer_setup.xcconfig`
- hardware destination must use a physical UDID for `xcodebuild`/`devicectl`

Reduced coverage behavior:
- fixture-dependent wrappers may emit `skip_reduced_coverage` when fixture startup fails and reduced coverage is explicitly allowed
- monolithic `verify-fast --allow-no-fixture` skips fixture-dependent tests and records that reduced scope in report notes
- report entries now include `lane`, `resource_group`, `worker`, and `coverage_mode`

## Gate Mapping (Current)

- `Prep / Baseline`: `baseline-sync`
- `G0 Toolchain`: checks team/bundle/assets/simulator and optional fixture availability
- `G1 Compile`: simulator `build-for-testing` plus generic iOS compile
- `G2 Test`: currently monolithic in `verify-fast`; shard lane scripts exist
- `G3 Runtime Smoke`: `deploy-device` (build, install, launch)
- `G4 Domain Gates`: lane scripts exist for key domains; `verify-full` still records this gate as pending manual
- `G8 UX/Product`: staged by `acceptance` for manual completion
- `G9 Release`: currently manual/pending in lane manifest

## Artifacts And Reports

All loop output is written under:
- `.build/completion-loop/<timestamp>/`

Primary report:
- `.build/completion-loop/<timestamp>/report.json`

Lane runners additionally write:
- `lane-metadata.json`
- `lane-outputs.env`
- per-lane logs in lane artifact directories
