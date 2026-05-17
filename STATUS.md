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
- Swift wallet and blockchain explorer parity foundation is implemented, tested, pushed, and #102 is closed.
- All GitHub issues are closed as of May 17, 2026 after closing completed Swift chain-trust parent issues #59-#66.

## Active Task

## Swift Chain Trust Parent Issue Closure

- [x] Confirm open GitHub issues #59-#66 are the remaining chain-trust parent issues.
- [x] Verify the completed Swift chain-trust implementation still passes locally.
- [x] Close completed parent issues #59-#66 with implementation and verification notes.
- [x] Commit and push only scoped status updates.

## A2UI Imageboard Demo App

- [x] Create tracker issue for the imageboard demo app (#112).
- [x] Inspect agent app manifest, app-store metadata, and registry test surfaces.
- [x] Add an Imageboard A2UI app with boards, threads, image upload metadata, comments, and safe posting instructions.
- [x] Add focused registry tests for imageboard metadata, approval gates, and rendered task instructions.
- [x] Verify relevant Rust/frontend tests locally.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #112.

## Swift Wallet Capability Contracts

- [x] Create tracker issue for wallet and chain capability contracts (#111).
- [x] Inspect Swift A2UI, MCP, runtime bridge, wallet/explorer, and chain-trust surfaces.
- [x] Add typed wallet and chain capability contracts for local apps and MCP servers.
- [x] Add native embedded wallet creation as an alternative to external wallet connection.
- [x] Render install/runtime permission and transaction approval surfaces in Swift UI.
- [x] Add focused tests for capability defaults, permission enforcement, transaction requests, policy receipts, and embedded wallet creation.
- [x] Verify the Swift build/test lane locally.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #111.

## Web Landing Page Refresh

- [x] Create tracker issue for web landing page refresh (#110).
- [x] Inspect current `web` landing page structure and existing messaging.
- [x] Update landing page copy/sections for A2UI app store apps, DOM traversal, wallet/explorer, and crypto chain-trust work.
- [x] Keep claims accurate around approval gates, local policy receipts, and production verifier limitations.
- [x] Verify the web build locally.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #110.

## A2UI Agent App Store UI

- [x] Create tracker issue for app-store style A2UI agent app UI (#109).
- [x] Replace the raw app runner list with store cards, install state, and open/run flow.
- [x] Keep A2UI, DOM traversal, and approval-gate metadata visible on app cards.
- [x] Add focused frontend tests for install, open, quick prompt, launch, and schedule behavior.
- [x] Verify relevant frontend tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #109.

## A2UI Agent App Concepts

- [x] Create GitHub issue for Shopping and Returns Agent (#103).
- [x] Create GitHub issue for Form-Filling Concierge (#104).
- [x] Create GitHub issue for Conference Trip Agent (#105).
- [x] Create GitHub issue for Travel Disruption Rebooker (#106).
- [x] Create GitHub issue for Travel Booker (#107).
- [x] Create GitHub issue for Apartment and Stay Finder (#108).

## A2UI Travel Booker Agent App

- [x] Triage existing agent app registry, A2UI surface, and DOM traversal tools.
- [x] Create tracker issue for Travel Booker (#107).
- [x] Add Travel Booker to the agent app manifest with A2UI and DOM traversal instructions.
- [x] Add focused tests for Travel Booker metadata and rendered task instructions.
- [x] Verify relevant Rust/frontend tests.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #107.

## A2UI Agent App Catalog Completion

- [x] Confirm remaining demo app issues are open and not blocked by product decisions (#103, #104, #105, #106, #108).
- [x] Add Travel Disruption Rebooker, Conference Trip Agent, Form-Filling Concierge, Shopping and Returns Agent, and Apartment and Stay Finder to the agent app manifest.
- [x] Add focused registry tests for the complete A2UI app catalog.
- [x] Verify relevant Rust/frontend tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issues #103, #104, #105, #106, and #108.

## Swift Build Warning Cleanup

- [x] Inspect reported app category, SwiftUI `onChange`, and MCP default-server diagnostics.
- [x] Add an app category to the Swift Info.plist.
- [x] Update deprecated SwiftUI `onChange` usage.
- [x] Make MCP default server seeds usable from nonisolated runtime configuration.
- [x] Verify the Swift/Xcode build locally.
- [x] Commit and push only scoped files.

## Swift A2UI Token Rendering

- [x] Inspect `a2ui-swift` package shape and current Swift package setup.
- [x] Import `A2UISwiftUI`/`A2UISwiftCore` into the Xcode project.
- [x] Add a Swift A2UI token renderer model backed by the package parser/view model.
- [x] Add a top-level A2UI panel with sample token rendering and action logging.
- [x] Add focused unit/UI tests for token parsing and panel visibility.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Swift MCP Server Connection UI

- [x] Inspect existing desktop MCP profile support and Swift runtime surfaces.
- [x] Add Swift MCP server configuration/status models and bridge actions.
- [x] Add a top-level MCP panel for enabling and connecting HTTP, WebSocket, and stdio servers.
- [x] Add focused unit/UI tests for MCP server connection UI.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Swift Wallet Top-Level Navigation

- [x] Inspect current Swift panel/sidebar and wallet explorer surfaces.
- [x] Promote Wallet to a top-level browser panel and sidebar section.
- [x] Add focused tests for wallet panel navigation.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Swift Wallet And Blockchain Explorer Parity

- [x] Triage missing Swift blockchain explorer and wallet parity from #102.
- [x] Create tracker issue for Swift wallet/explorer parity (#102).
- [x] Add Swift wallet/explorer models for networks, accounts, balances, transfer previews, receipts, and explorer targets.
- [x] Seed explorer and wallet network coverage for Bitcoin, Ethereum/EVM/L2s, Solana, Cosmos/Tendermint, Substrate/Polkadot, Avalanche, TRON, XRP Ledger, Sui, and Aptos.
- [x] Extend the runtime bridge with portfolio state, network switching, preview, approval-gated signing receipts, and broadcast-unavailable labeling.
- [x] Add a Swift runtime wallet/explorer panel with chain trust labels and explorer links.
- [x] Add focused Swift unit tests for wallet/explorer behavior and trust labeling.
- [x] Verify Swift tests and macOS build.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #102.

## Swift Recents Navigation Bug

- [x] Triage recents/history navigation report from #101.
- [x] Create tracker issue for recents links not loading (#101).
- [x] Add a focused Swift regression test for opening recent/history entries.
- [x] Make the recents sidebar use the shared history-opening path.
- [x] Dedupe and move reopened history entries to the top.
- [x] Verify Swift tests and macOS build.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #101.

## Swift Move-Chain Trust Foundation Slice

- [x] Triage Sui/Aptos Move-chain trust-state gap from #67.
- [x] Create tracker issue for Swift Move-chain Sui/Aptos chain trust foundation (#100).
- [x] Add shared Swift Move-chain metadata for Sui/Aptos networks, endpoint config, checkpoint/ledger snapshot, committee/validator set, signature, object/account/transaction proof, verification result, and service snapshot models.
- [x] Add fixture-backed Sui checkpoint committee quorum and Aptos ledger-info validator quorum validation.
- [x] Add stale checkpoint/ledger detection and unsupported production verifier labeling.
- [x] Add local Sui object/transaction-effects and Aptos account/transaction proof verification bound to checkpoint/ledger roots.
- [x] Add weak quorum, stale, failed, and API/RPC fallback labeling.
- [x] Add Move service client contract and fixture-backed `services/chain-trust` endpoints for Sui and Aptos.
- [x] Bind Move-chain snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for chain routing, status modeling, stale detection, proof verification, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift XRP Ledger Chain Trust Foundation Slice

- [x] Triage XRP Ledger validated/fallback trust-state gap from #66.
- [x] Create tracker issue for Swift XRP Ledger chain trust foundation (#99).
- [x] Add Swift XRPL network metadata, endpoint config, validated ledger, UNL/trust-anchor, validation vote, account/trust-line/payment proof, verification result, and service snapshot models.
- [x] Add fixture-backed UNL quorum validation with configured/effective UNL assumptions.
- [x] Add stale validated-ledger detection and unsupported production verifier labeling.
- [x] Add local account, trust-line, and payment metadata proof verification bound to validated ledger roots.
- [x] Add weak quorum, stale, failed, and API/RPC fallback labeling.
- [x] Add XRPL service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind XRPL snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for routing, status modeling, stale detection, proof verification, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift TRON Chain Trust Foundation Slice

- [x] Triage TRON light-client/proof-verified fallback gap from #65.
- [x] Create tracker issue for Swift TRON chain trust foundation (#98).
- [x] Add Swift TRON network metadata, endpoint config, witness set, block header, account/token proof, receipt proof, verification result, and service snapshot models.
- [x] Add fixture-backed delegated-proof-of-stake witness quorum validation.
- [x] Add stale block detection and unsupported production light-client labeling.
- [x] Add local account/token and transaction receipt proof verification bound to block roots.
- [x] Add weak quorum, stale, failed, and API/RPC fallback labeling.
- [x] Add TRON service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind TRON snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for routing, status modeling, stale detection, proof verification, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Avalanche Chain Trust Foundation Slice

- [x] Triage Avalanche light-client gap from #64.
- [x] Create tracker issue for Swift Avalanche chain trust foundation (#97).
- [x] Add Swift Avalanche network/C-Chain metadata, endpoint config, accepted block, validator set, finality evidence, EVM proof bridge, verification result, and service snapshot models.
- [x] Add fixture-backed Snowman accepted-finality validation with validator-weight threshold checks.
- [x] Add C-Chain EVM account/storage/receipt proof verification bound to the accepted Avalanche block.
- [x] Add weak quorum, chain mismatch, stale, failed, and RPC fallback labeling.
- [x] Add Avalanche service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind Avalanche snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for routing, finality status, proof verification, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Polkadot/Substrate Chain Trust Foundation Slice

- [x] Triage Polkadot/Substrate light-client gap from #63.
- [x] Create tracker issue for Swift Polkadot/Substrate chain trust foundation (#96).
- [x] Add Swift Substrate chain spec metadata, endpoint config, finalized header, GRANDPA authority set, finality justification, conflict evidence, storage proof, verification result, and service snapshot models.
- [x] Add fixture-backed GRANDPA finality validation with authority-weight threshold checks.
- [x] Add local storage proof verification against finalized header state roots.
- [x] Add conflicting GRANDPA justification detection with explicit failed state and RPC fallback labeling.
- [x] Add Substrate service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind Substrate snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for chain-spec routing, finalized header status, storage proof verification, conflict handling, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Cosmos/Tendermint Chain Trust Foundation Slice

- [x] Triage Cosmos/Tendermint light-client gap from #62.
- [x] Create tracker issue for Swift Cosmos/Tendermint chain trust foundation (#95).
- [x] Add Swift Cosmos chain metadata, endpoint, Tendermint header, validator set, commit signature, trust-period, conflict evidence, and service snapshot models.
- [x] Add fixture-backed Tendermint header/commit validation with validator-power threshold checks.
- [x] Add trust-period expiry and conflicting commit detection with explicit stale/failed states.
- [x] Add Cosmos service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind Cosmos snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for chain routing, header verification, expiry, conflict handling, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Solana Chain Trust Foundation Slice

- [x] Triage Solana light-client gap from #61.
- [x] Create tracker issue for Swift Solana chain trust foundation (#94).
- [x] Add Swift Solana cluster, endpoint, slot/root, proof, transaction/account status, and service snapshot models.
- [x] Add local fixture-proof validation for account and transaction-status evidence.
- [x] Add stale slot/root detection and explicit RPC fallback labeling.
- [x] Add Solana service client contract and fixture-backed `services/chain-trust` endpoints.
- [x] Bind Solana snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for status modeling, stale detection, fallback, service contract, registry updates, and runtime refresh.
- [x] Verify local service checks plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Ethereum/EVM Light Client Foundation Slice

- [x] Triage Ethereum/EVM light-client gap from #60.
- [x] Create tracker issue for Swift Ethereum/EVM light-client foundation (#93).
- [x] Add Swift Ethereum/EVM chain, endpoint, checkpoint, header, proof, and service snapshot models.
- [x] Add local verifier primitives for fixture-backed account/storage/receipt/log evidence.
- [x] Add Ethereum/EVM service client contract for `./services` chain-trust status and proof verification endpoints.
- [x] Extend `services/chain-trust` with fixture-backed Ethereum/EVM status and proof verification endpoints.
- [x] Bind Ethereum/EVM snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests for routing, proof validation, fallback, registry updates, and runtime refresh.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Local Chain Trust Bitcoin Service Slice

- [x] Triage remaining Bitcoin service gap from #59.
- [x] Create tracker issue for local chain-trust Bitcoin service (#92).
- [x] Add `services/chain-trust` workspace package with health, snapshot, lint, and self-test commands.
- [x] Expose fixture-backed Bitcoin status endpoints for the Swift `/v1/bitcoin/status` contract.
- [x] Expose Bitcoin transaction inclusion verification endpoints that check header hash and Merkle evidence locally.
- [x] Add root workspace script coverage for the chain-trust service.
- [x] Verify service lint/self-test plus Swift tests/build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Bitcoin Light Client Foundation Slice

- [x] Triage Bitcoin SPV/compact-filter gap from #59.
- [x] Create tracker issue for Swift Bitcoin light-client verifier foundation (#91).
- [x] Add Swift Bitcoin header/checkpoint/Merkle proof/service snapshot/sync models.
- [x] Add a Swift Bitcoin light-client service endpoint configuration and HTTP client contract for future `./services` chain-trust endpoints.
- [x] Implement local verifier primitives for header hashing, chain-work ordering, Merkle inclusion, stale headers, and reorg detection.
- [x] Bind Bitcoin light-client snapshots into the shared chain trust registry/runtime status.
- [x] Add focused Swift unit tests including known Bitcoin genesis header fixture coverage.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift Chain Trust Registry Foundation Slice

- [x] Triage shared chain-trust registry gap from #68.
- [x] Create tracker issue for Swift chain trust registry foundation (#90).
- [x] Add shared Swift chain registry/status/proof/checkpoint models.
- [x] Seed supported chain families for Bitcoin, Ethereum/EVM/L2s, Solana, Cosmos/Tendermint, Polkadot/Substrate, Avalanche, TRON, XRP Ledger, Sui, and Aptos.
- [x] Surface chain trust state in Swift runtime status/UI without overstating gateway/RPC fallback.
- [x] Bind AFMarket settlement evidence into the chain trust registry.
- [x] Add focused Swift unit tests for registry coverage, fallback labeling, runtime status, and AFMarket settlement binding.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift LLM Router Service Adapter Slice

- [x] Triage remaining provider/tool-call gap from #72.
- [x] Create tracker issue for Swift LLM router service adapter (#89).
- [x] Add Swift LLM router endpoint configuration, snapshot, model, completion, usage, and tool-call models.
- [x] Add a Swift LLM router service client for health, model discovery, and completion calls.
- [x] Surface the router-backed provider in the Swift model registry/runtime status.
- [x] Route selected Swift LLM conversation runs through the LLM router before AFMarket/local fallback.
- [x] Record router completion and proposed tool-call state in Copilot activity.
- [x] Add focused Swift unit tests for discovery, completion payloads, runtime routing, model selection, and activity events.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift OpenMind Correction And Review Slice

- [x] Triage remaining OpenMind/BrIAn correction and review gap from #70.
- [x] Create tracker issue for memory correction and review affordances (#88).
- [x] Add Swift OpenMind review-task and correction outcome models.
- [x] Add direct HTTP and JSON-RPC client support for review tasks and corrections.
- [x] Surface review-task and latest correction state in the Swift runtime/Copilot UI.
- [x] Add Copilot activity events for memory correction requests and outcomes.
- [x] Add focused Swift unit tests for review resources, correction calls, and view-model behavior.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

## Swift OpenMind MCP Transport Negotiation Slice

- [x] Triage remaining OpenMind/BrIAn transport negotiation gap from #70.
- [x] Create tracker issue for OpenMind MCP transport negotiation (#87).
- [x] Add Swift OpenMind transport preference/configuration models.
- [x] Add negotiated transport metadata to OpenMind runtime/capability state.
- [x] Negotiate direct HTTP versus JSON-RPC HTTP bridge capabilities.
- [x] Add JSON-RPC tool/resource wrappers while preserving direct HTTP compatibility.
- [x] Normalize JSON-RPC structuredContent responses into existing typed models.
- [x] Add focused Swift unit tests for negotiation, recall, resources, and writeback.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-openmind-transport-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-openmind-transport-tests -only-testing:dBrowserTests` passed.

## Swift AFMarket Proof And Settlement Verification Slice

- [x] Triage remaining AFMarket proof/settlement verification gap from #69.
- [x] Create tracker issue for proof and settlement verification reporting (#86).
- [x] Add Swift AFMarket verification report and check models.
- [x] Decode richer AFMarket proof, public input, escrow, transaction, and deadline metadata.
- [x] Verify task, output commitment, proof public input, and nonce binding where present.
- [x] Classify mock, locally consistent, pending, anchored, and failed verification states.
- [x] Surface verification summaries and checks in Copilot activity/runtime suggestions.
- [x] Add focused Swift unit tests for production-like and local/mock verification reports.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-afmarket-verification-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-afmarket-verification-tests -only-testing:dBrowserTests` passed.

## Swift AFMarket Marketplace Runner Pack Slice

- [x] Triage remaining AFMarket marketplace pack gap from #69.
- [x] Create tracker issue for marketplace runner-pack ingestion (#85).
- [x] Add optional Swift AFMarket marketplace endpoint configuration.
- [x] Add typed Swift marketplace runner-pack, policy, prompting, royalty, and hash models.
- [x] Merge marketplace packs into Swift AFM service snapshots and runner-pack selection.
- [x] Surface marketplace pack counts and policy/royalty metadata in runtime status.
- [x] Add focused Swift unit tests for marketplace decoding, pack merging, and Copilot surfacing.
- [x] Verify local Swift tests and build.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-afmarket-marketplace-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-afmarket-marketplace-tests -only-testing:dBrowserTests` passed.

## Swift AFMarket V1 Registry And Route Slice

- [x] Triage remaining AFMarket v1 compatibility gaps from #69.
- [x] Create tracker issue for registry bundle and route lease metadata (#84).
- [x] Add typed Swift AFMarket expert, bundle, route lease, and settlement metadata models.
- [x] Extend AFMServicesClient snapshot with `/v1/experts` and `/v1/bundles` support plus local fallback.
- [x] Extend AFMServicesClient route with `/v1/route` request metadata and local `/route` fallback.
- [x] Surface route lease, reward, SLA, and chain metadata in Copilot/runtime status.
- [x] Add focused Swift unit tests for v1 registry, routing, fallback, and Copilot summaries.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-afmarket-v1-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-afmarket-v1-tests -only-testing:dBrowserTests` passed.

## Swift OpenMind Evidence Bundle And Step-Up Slice

- [x] Triage the remaining BrIAn/OpenMind evidence and step-up gaps from #70.
- [x] Create tracker issue for evidence bundle recall and step-up requests (#83).
- [x] Add typed Swift OpenMind evidence bundle and step-up request models.
- [x] Extend OpenMindMemoryClient recall with evidence bundle retrieval and resilient fallback.
- [x] Add a Swift step-up request action using the denied recall intent.
- [x] Surface evidence bundle and step-up request state in Copilot/OpenMind UI.
- [x] Add focused Swift unit tests for evidence bundles and step-up requests.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-openmind-evidence-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-openmind-evidence-tests -only-testing:dBrowserTests` passed.

## Swift LLM Conversation Persistence Slice

- [x] Triage the remaining persistence gap from #72.
- [x] Create tracker issue for persisted Swift LLM conversation state (#82).
- [x] Add a JSON-backed Swift LLM conversation store with ephemeral test support.
- [x] Load and validate persisted conversation/model state in BrowserViewModel.
- [x] Persist conversation mutations after messages, model switches, context events, and fallbacks.
- [x] Add a UI action to start a fresh persisted conversation.
- [x] Add focused Swift unit tests for restore and reset behavior.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-llm-persistence-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-llm-persistence-tests -only-testing:dBrowserTests` passed.

## Swift LLM Conversation And Model Switching Slice

- [x] Triage open Swift LLM issue #72 and choose the first implementation slice.
- [x] Create tracker issue for the conversation/model switching work (#81).
- [x] Add provider-neutral Swift conversation ledger models.
- [x] Add Swift model registry and context rendering/compression helpers.
- [x] Wire BrowserViewModel conversation send, model switching, and Copilot run continuity.
- [x] Replace the narrow Copilot prompt/result surface with a chat-style model-aware UI.
- [x] Add focused Swift unit tests.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-llm-chat-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-llm-chat-tests -only-testing:dBrowserTests` passed.

## Swift OpenMind Governed Writeback And Continuity Slice

- [x] Triage remaining BrIAn/OpenMind gaps from #70.
- [x] Create tracker issue for writeback/continuity work (#80).
- [x] Add typed OpenMind continuity/posture/resource snapshot models.
- [x] Extend OpenMindMemoryClient with continuity/posture refresh and explicit writeback metadata.
- [x] Add a user-triggered Copilot memory writeback action.
- [x] Surface writeback outcome and BrIAn posture/continuity in Swift UI.
- [x] Add focused Swift unit tests.
- [x] Verify local builds/tests.
- [x] Commit and push only scoped files.
- [x] Update and close completed GitHub issues.

Validation notes:

- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-openmind-writeback-build` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-openmind-writeback-tests -only-testing:dBrowserTests` passed.

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
