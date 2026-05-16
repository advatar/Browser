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

## iOS Panel Navigation and IPFS Rendering

- [x] Add real panel content for History, Bookmarks, Copilot, and Runtime.
- [x] Add iOS panel controls that visibly switch between browser and panels.
- [x] Add focused unit/UI tests for IPFS starting points rendering and bridge navigation.
- [x] Run local Swift/Xcode validation.
- [x] Commit the panel and IPFS rendering work semantically.

## macOS WKWebView Network Entitlement

- [x] Add a macOS sandbox entitlement with outbound network client access.
- [x] Attach platform-specific entitlements in the Xcode project.
- [x] Verify the macOS destination build.

## Decentralized Web Starting Points

- [x] Add curated IPFS/IPNS starting points to the iOS home screen.
- [x] Route starting points through the existing decentralized runtime bridge.
- [x] Add focused tests for the starting-point data.
- [x] Run local Swift/Xcode validation.
- [x] Commit the starting-point work semantically.

## Push All Dangling Work

- [ ] Commit semantic groups for all current changes.
- [ ] Commit any remaining miscellaneous changes in a final cleanup commit.
- [ ] Push all resulting commits.

## Runtime Button Details

- [x] Make runtime feature tiles clickable.
- [x] Add deeper runtime feature explanations.
- [x] Add focused tests for explanation coverage.
- [x] Run local Swift/Xcode validation.
- [x] Commit only files touched for this fix.

## iOS SwiftUI Compatibility Fix

- [x] Move address-field input modifiers behind platform-safe SwiftUI branches.
- [x] Verify the Xcode build after the compatibility fix.
- [x] Commit only files touched for this fix.

## iOS Runtime Bridges

- [x] Add a Swift runtime bridge contract for decentralized protocols, Copilot, wallet, and downloads.
- [x] Wire browser navigation and runtime status to the bridge.
- [x] Add focused bridge unit tests.
- [x] Run local Swift/Xcode validation.
- [x] Commit only files touched for this bridge work.

## iOS Xcode Integration

- [x] Inspect the new `swift/dBrowser` Xcode project structure.
- [x] Integrate the existing browser runtime experience into the Swift app shell.
- [x] Add focused tests for the iOS integration layer.
- [x] Run local Swift/Xcode and relevant frontend validation.
- [x] Commit only files touched for this integration.

## Architecture Review: ZK, AI, and iOS Feasibility

- [x] Review project implementation for correctness risks and architecture gaps.
- [x] Identify zero-knowledge proof opportunities.
- [x] Identify stronger AI integration opportunities.
- [x] Assess iOS feasibility from the current Tauri/Rust architecture.
- [x] Run local validation commands for the reviewed codebase.

## REVIEW.md Remediation

- [x] Resolve high dynamic execution review finding.
- [x] Complete secret/config material audit and document ownership.
- [x] Gate or document debug/CORS/insecure-transport scanner hits.
- [x] Remove or classify remaining HTML injection scanner hits.
- [x] Document nested manifest and package-manager ownership.
- [x] Harden runtime failure shortcuts identified in review evidence.
- [x] Run local validation and commit remediation.

## Code Review Gap Closure

- [x] Harden static review follow-ups: DOM injection sinks and panic/unsafe hotspots (#6).

## Walkthrough UX Remediation

- [x] Create GitHub issues for all 42 findings in `walkthrough.md` (#7-#48).
- [x] Fix P0 walkthrough blockers first: status bar production state, security indicator state, dead developer tools control, standard shortcuts, inline agent approvals, and command-palette settings action.
- [x] Fix first P1 tab/accessibility items: auto-create a replacement tab after closing the last tab, and add ARIA tab roles to the tab strip.
- [x] Fix tab affordance follow-ups: drag-drop insertion feedback, discoverable overflow controls, and stronger active tab state (#9-#11).
- [x] Fix tab-close focus management for keyboard users (#44).
- [x] Fix settings walkthrough cluster: distinct system theme state, explicit settings save/revert/reset flow, and batched backend sync (#15, #31, #32, #45).
- [x] Consolidate repeated NavigationBar tooltip providers (#17).
- [x] Fix downloads sidebar search and indeterminate progress affordances (#18, #21).
- [x] Fix bookmark edit action and durable bookmark persistence (#19, #20).
- [x] Optimize History and Downloads store subscriptions (#46).
- [x] Animate sidebar collapse and expand width changes (#22).
- [x] Fix content/homepage loading resilience: richer page loading feedback, user-facing webview errors, homepage fallback content, and probe skeleton/timeout (#23, #24, #26, #27).
- [x] Centralize and test native content bounds calibration (#25).
- [x] Resolve command palette URL-vs-command precedence (#35).
- [x] Add keyboard shortcut discovery dialog and command (#42).
- [x] Remove leftover Vite scaffold CSS and Lovable package metadata (#47, #48).
- [x] Show Tor routing status feedback in Settings (#33).
- [x] Improve Copilot run detail summaries and top-up confirmation (#40, #41).
- [x] Populate Site Info with backend security audit and certificate data (#36).
- [x] Add wallet connection and management dialog (#16).
- [x] Decompose CopilotPanel into focused section components (#37).
- [x] Add conversational Copilot interaction model (#39).
- [x] Run focused frontend validation for the completed walkthrough fixes.
- All walkthrough follow-ups created from `walkthrough.md` are fixed and closed in GitHub issues #7-#48.

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
