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

## Swift AFMarket Node And Settlement Slice

- [x] Triage remaining AFMarket implementation gaps from #69.
- [x] Create tracker issue for node/attestation/settlement work (#79).
- [x] Add a local `./services/node` AFM node-agent stub and workspace scripts.
- [x] Extend Swift AFM service configuration and snapshots with node availability.
- [x] Add Swift install, dispatch, attestation, proof, and settlement models.
- [x] Route service-backed Copilot through node install/dispatch when available.
- [x] Surface AFMarket install, dispatch, attestation, proof, and settlement state in Swift UI/activity.
- [x] Add focused Swift and service tests.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `npm --prefix services/node test` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-afm-node-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-afm-node-tests -only-testing:dBrowserTests` passed.

## Swift Service-Backed Strawberry Integrations

- [x] Triage remaining Swift Strawberry service issues (#69 and #70).
- [x] Create tracker issue for the implementation batch (#78).
- [x] Expand Swift AFM service state so the app surfaces router, registry, and pipelines data from `./services`.
- [x] Add selected runner-pack intent to Swift Copilot requests and service-backed job enqueue.
- [x] Add typed OpenMind/BrIAn memory capability, access, recall, and writeback models.
- [x] Integrate governed memory recall states into Copilot run activity.
- [x] Add focused Swift unit tests for AFM service surfacing and memory outcomes.
- [x] Verify the Swift/Xcode build and focused tests locally.
- [x] Commit and push only the scoped service integration changes.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-service-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-service-tests-2 -only-testing:dBrowserTests` passed.

## Swift Strawberry Open Issues Build

- [x] Triage open GitHub issues and select the Swift Strawberry sequence (#50-#58).
- [x] Create tracker issue for the implementation batch (#77).
- [x] Implement WKWebView automation, DOM query/action, and page snapshot primitives (#50-#53).
- [x] Implement Copilot activity, cancellation, credit metering, workflows, concurrent runs, and Smart History recall (#54-#58).
- [x] Add focused Swift unit tests for the new Strawberry primitives and surfaces.
- [x] Verify the Swift/Xcode build and focused tests locally.
- [x] Commit and push only the scoped Strawberry changes.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-strawberry-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-strawberry-tests -only-testing:dBrowserTests` passed.

## KeyMeIn Secret Handling Decision

- [x] Inspect `KeyMeIn/` docs, browser integration notes, SDK notes, and security checklist.
- [x] Create a GitHub issue deciding whether KeyMeIn should keep dBrowser wallet secrets (#75).
- [x] Capture the recommended role for KeyMeIn versus Keychain/Secure Enclave and hardware-backed signers.
- [x] Verify the status-only change locally.
- [x] Commit and push only the scoped status update.

## Swift Blockchain Wallet Code Investigation

- [x] Inspect current dBrowser wallet simulator, architecture docs, and light-client issue map.
- [x] Research primary-source Swift/native SDK options for Bitcoin, Ethereum/EVM, Solana, Cosmos, Substrate, Avalanche, TRON, XRPL, Sui, and Aptos wallets.
- [x] Create a GitHub issue with the recommended Swift wallet code stack and investigation plan (#76).
- [x] Capture the recommended shared wallet architecture and per-chain library choices.
- [x] Verify the status-only change locally.
- [x] Commit and push only the scoped status update.

Validation notes:

- `git diff --check -- STATUS.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Kline Runtime Boundary Decision

- [x] Inspect `../Kline` app/docs/package structure and identify its runtime boundary.
- [x] Create a GitHub issue deciding whether all of Kline should be integrated or kept as a separate agent runtime (#74).
- [x] Capture overlaps with dBrowser Swift packages, likely integration boundaries, and recommendation.
- [x] Verify the status-only change locally.
- [x] Commit and push only the scoped status update.

Validation notes:

- `git diff --check -- STATUS.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## OpenClaw Integration Investigation Plan

- [x] Inspect `../clawdex/openclaw` top-level product docs, package structure, Swift companion app surfaces, gateway/MCP/plugin/memory areas, and channel scope.
- [x] Create a GitHub issue to investigate whether integrating all of OpenClaw into dBrowser makes sense (#73).
- [x] Capture pros, cons, overlaps, and likely integration boundaries.
- [x] Verify the documentation/status-only change locally.
- [x] Commit and push only the scoped status update.

Validation notes:

- `git diff --check -- STATUS.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Documentation Consolidation Plan

- [x] Inventory existing `./docs` narrative files and supporting metadata.
- [x] Create a GitHub issue for consolidating docs into one current architecture and plan (#71).
- [x] Create a GitHub issue for Swift LLM desktop UI and context-preserving model switching (#72).
- [x] Read the current docs and identify the architecture, integrations, and implementation roadmap to preserve.
- [x] Consolidate narrative docs into one canonical current architecture and plan.
- [x] Verify Markdown hygiene and local build/test requirements.
- [x] Commit and push only the scoped documentation/status updates.

## Swift BrIAn Personal Memory Integration Plan

- [x] Inspect `../OpenMind/BrIAn` README, OpenMind MCP client/server, OMPS routes, and control-plane notes.
- [x] Create a GitHub issue for integrating Swift Strawberry equivalence with BrIAn/OpenMind MCP (#70).
- [x] Update the Swift Strawberry plan with BrIAn personal-memory integration requirements.
- [x] Verify the documentation-only change locally.
- [x] Commit and push only the scoped status and plan updates.

Validation notes:

- `git diff --check -- README.md STATUS.md STRAWBERRY_SWIFT.md docs/ARCHITECTURE.md docs/README.md docs/ai/system_map.yaml docs/ai/dev_commands.yaml` passed.
- `LC_ALL=C grep -n '[^ -~]' README.md STATUS.md STRAWBERRY_SWIFT.md docs/ARCHITECTURE.md docs/README.md docs/ai/system_map.yaml docs/ai/dev_commands.yaml || true` produced no non-ASCII matches.
- `ruby -e "require 'yaml'; ARGV.each { |f| YAML.load_file(f); puts f }" docs/ai/system_map.yaml docs/ai/dev_commands.yaml` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.

## Swift AFMarket Integration Plan

- [x] Inspect `../AFMarket` marketplace, router, registry, node, contracts, pipelines, and Swift ZKAI surfaces.
- [x] Create a GitHub issue for integrating Swift Strawberry equivalence with `../AFMarket` (#69).
- [x] Update the Swift Strawberry plan with AFMarket integration requirements.
- [x] Verify the documentation-only change locally.
- [x] Commit and push only the scoped status and plan updates.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.

## Swift Strawberry Equivalence Plan

- [x] Create GitHub issues for each Swift Strawberry equivalence step (#50-#58).
- [x] Create GitHub issues for major-chain Swift light-client integration (#59-#68).
- [x] Draft a Swift-app-specific Strawberry equivalence plan from the existing Rust plan.
- [x] Verify the local Swift project still builds/tests after the documentation change.
- [x] Commit and push only the scoped status and plan updates.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- Full `xcodebuild test` still fails in existing macOS UI tests: `dBrowserUITests.testExample`, `testGatewayStartingPointsRenderRequiredURLs`, `testIPFSStartingPointsRenderAndOpenThroughBridge`, and `testPanelButtonsShowPanelContent`.

## iOS Architecture Light-Client Emphasis

- [x] Inspect current light-client docs and blockchain runtime surface.
- [x] Update the architecture/runtime explanations to make embedded blockchain light clients first-class.
- [x] Add focused tests for light-client architecture coverage.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push the scoped light-client architecture change.

## iOS Architecture Overview Button

- [x] Inspect ZeroK and current AFM runtime surfaces.
- [x] Add an architecture overview feature button covering AF Market, ZeroK, and LLM Gateway.
- [x] Add focused tests for architecture explanation coverage.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push the scoped architecture overview change.

## Zero Knowledge Gateway Entry Points

- [x] Capture required gateway URLs for the Swift shell.
- [x] Add first-class LLM OS and zero-knowledge gateway navigation targets.
- [x] Add focused tests for required gateway URLs.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit the scoped gateway change.

## iOS URL Autocomplete

- [x] Inspect Swift browser history and address-entry flow.
- [x] Add history-backed URL autocomplete suggestions.
- [x] Add focused unit tests for autocomplete matching and ordering.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit the scoped autocomplete change.

## iOS Gemma MLX Bundle

- [x] Search the wider `~/dev/advatar` workspace for existing MLX-optimized Gemma artifacts.
- [x] Select the iPhone-sized Gemma bundle target and record the local source path.
- [x] Wire the Swift app to the current MLX Swift LM VLM package.
- [x] Add focused unit tests for model selection and package-backed model configuration.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push the scoped Gemma integration.

## Swift AFM Services Integration

- [x] Create GitHub issue for Swift service-backed runtime work (#49).
- [x] Add Swift runtime bridge configuration and client for AFM router, registry, and pipelines services.
- [x] Wire Swift Copilot/status flows through those services with local fallback.
- [x] Add focused unit tests for service-backed and fallback behavior.
- [x] Verify Swift/Xcode build and AFM service package tests locally; Swift unit test execution is blocked by unrelated PersonaPlex/MLX test-link failures.
- [x] Commit and push the scoped changes.

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

- [x] Commit semantic groups for all current changes.
- [x] Commit any remaining miscellaneous changes in a final cleanup commit.
- [x] Push all resulting commits.

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
