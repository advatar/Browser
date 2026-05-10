# Status

## Strawberry Gap Closure

- [x] Add smart-history recall in the Rust backend and expose it to the runtime UI.
- [x] Add scheduled Agent App workflows with persistence and a background runner.
- [x] Add a concurrent-runs surface in the Copilot UI for multiple active/recent runs.
- [x] Update validation and AI/docs metadata for the new workflow surface.
- [x] Run the full relevant Rust and frontend test suites.

## Current Status

- Strawberry parity work is implemented and committed.
- Automated validation is green across Rust, the runtime frontend, and the Playwright UI lane.
- Remaining follow-up is manual smoke from `VALIDATE.md`.
- The Tauri/Vite dev stack has been cold-restarted after clearing build artifacts, and the fresh dev binary is running.
- `ipfs://` and `ipns://` navigation now resolves through the embedded browser node instead of rewriting through a public gateway.
- Production hardening changes are implemented and validated with `cargo test -p gui`, `npm --prefix orbit-shell-ui run test`, and `npm --prefix orbit-shell-ui run build`.

## Active Task

## Walkthrough UX Remediation

- [x] Create GitHub issues for all 42 findings in `walkthrough.md` (#7-#48).
- [x] Fix P0 walkthrough blockers first: status bar production state, security indicator state, dead developer tools control, standard shortcuts, inline agent approvals, and command-palette settings action.
- [x] Fix first P1 tab/accessibility items: auto-create a replacement tab after closing the last tab, and add ARIA tab roles to the tab strip.
- [x] Run focused frontend validation for the completed walkthrough fixes.
- Remaining walkthrough follow-ups are tracked in the open GitHub issues from #8-#48.

## Signed DMG Distribution

- [x] Create a signed macOS DMG with the available local Apple Development identity.
- [x] Verify the packaged app/DMG locally and record the output artifact.
- [x] Gate production DMG builds on Developer ID signing and notarization credentials.

## Production Hardening

- [x] Enforce navigation security policy in the runtime instead of treating it as advisory state.
- [x] Remove sensitive IPC payload logging from release builds and make telemetry/logging opt-in for shipped binaries.
- [x] Replace timer-based page state in the runtime UI with native tab/page-load events from Tauri.
- [x] Turn downloads into a real background subsystem with event updates and only expose supported actions in the UI.
- [x] Gate browser automation capabilities by platform so unsupported desktop targets do not advertise broken agent tools.
- [x] Standardize CI on the supported runtime/frontend path and stop relying on the broken legacy frontend npm lane.
- [x] Align docs and defaults with the actual runtime architecture, including decentralized protocol handling and telemetry behavior.
