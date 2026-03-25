# Blink Acceptance Checklist (G8 / G9)

Use `scripts/ios/acceptance` first. It copies this checklist into:
- `.build/completion-loop/<timestamp>/g8-ux-product/ACCEPTANCE_CHECKLIST.md`

Record evidence (screenshots, video, notes, failures) next to that copied file.

## G8 UX / Product

- Confirm `G0`, `G1`, `G2`, and `G3` are already green in `report.json` before manual acceptance.
- Cold launch the Debug free-build on the iPad and confirm the initial shell is usable.
- Create a new shell, switch shells, and close one shell.
- Open Config, change a safe setting, and return without crash.
- Open Snippets and dismiss without crash.
- Validate SSH login from device to fixture host (`<LocalHostName>.local` by default) with expected test credentials.
- Run one SCP transfer and one SFTP transfer against fixture content.
- Open Blink File Provider content from Files.app and verify browse/open/delete.
- Validate external keyboard modifiers and smart keys if a keyboard is available.
- Exercise pinch, swipe, and menu interactions on device.
- Background and resume the app; confirm sessions are still usable.
- Change network (if possible) and confirm reconnect behavior is acceptable.
- If any lane in `lanes.json` is still marked `manual` for `G4`, treat that domain as manual acceptance scope and attach evidence.

## G9 Release

- Run paid-build / RevenueCat sanity on a non-free build configuration.
- Confirm branch CI passed expected fast-loop checks.
- Review `.build/completion-loop/<timestamp>/report.json` for lane-level statuses and coverage mode.
- Ensure any `skip_reduced_coverage` entries have explicit justification in release notes for the branch.
