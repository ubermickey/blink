# Blink Feature Matrix (v5 Lanes)

This matrix tracks coverage against the current lane model in `scripts/ios/lanes.json`.
If a lane is marked `manual` there, treat automation as pending even if a script exists locally.

| Area | Primary Gates / Lanes | Automation Status | Notes |
| --- | --- | --- | --- |
| Terminal sessions | `G2` (`g2_core`), `G8` (`g8_acceptance`) | Mixed (implemented + manual) | Core test automation exists; real interaction quality remains manual on iPad. |
| SSH auth / channels | `G2` (`g2_core`), `G4` (`g4_ssh_auth`) | Mixed (pending G4 wiring) | `G2` includes `SSHTests`; manifest still marks `g4_ssh_auth` as pending/manual. |
| Mosh bootstrap | `G2` (`g2_core`), `G4` (`g4_mosh_bootstrap`) | Mixed (pending G4 wiring) | Bootstrap checks run in tests; explicit G4 lane is still pending in manifest. |
| SCP / SFTP | `G2` (`g2_files`), `G4` (`g4_scp_sftp`) | Mixed (lane script present, manifest pending) | `g4_scp_sftp.sh` exists and seeds isolated fixture roots; `lanes.json` still flags manual. |
| File Provider | `G2` (`g2_files`), `G4` (`g4_file_provider`), `G8` | Mixed (lane script present, manifest pending) | Automated tests plus manual Files.app handoff in acceptance. |
| Config | `G2` (`g2_core`, `g2_ui_smoke`), `G8` | Mixed | UI smoke shard exists; acceptance retains deep settings checks. |
| Snippets | `G2` (`g2_code_snippets`, `g2_ui_smoke`), `G8` | Mixed | Simulator shard exists; end-to-end usability stays in manual acceptance. |
| BlinkCode | `G2` (`g2_code_snippets`), `G4` (`g4_blinkcode`) | Mixed (lane script present, manifest pending) | Dedicated `g4_blinkcode.sh` lane exists; manifest command wiring is pending. |
| Gestures / keyboard / smart keys | `G8` (`g8_acceptance`) | Manual | Device-specific UX checks remain manual by design. |
| Split View / multitasking | `G8` (`g8_acceptance`) | Manual | Real-device only. |
| Free-build runtime stubs | `G1`, `G4` (`g4_free_build_runtime`) | Mixed (lane script present, manifest pending) | Script validates `BLINK_FREE_BUILD` contract and simulator launch behavior. |
| Paid build / RevenueCat | `G9` (`g9_release`) | Manual / pending automation | Out of default free-build path; still marked manual in manifest. |
