# Status

## Strawberry Gap Closure

- [x] Add smart-history recall in the Rust backend and expose it to the runtime UI.
- [x] Add scheduled Agent App workflows with persistence and a background runner.
- [x] Add a concurrent-runs surface in the Copilot UI for multiple active/recent runs.
- [x] Update validation and AI/docs metadata for the new workflow surface.
- [x] Run the full relevant Rust and frontend test suites.

## Current Status

- dBrowser is now a native Swift app under `swift/dBrowser`.
- `docs/ARCHITECTURE.md` is the canonical current architecture and implementation plan.
- Deprecated Rust/Tauri planning, validation, review, and roadmap documents have been moved to `archive/deprecated-documents/`.
- Current validation uses the Swift/Xcode build and focused Swift test lane documented in `README.md`.
- Swift wallet and blockchain explorer parity foundation is implemented, tested, pushed, and #102 is closed.
- Decentralized protocol content-loading work is active under #118-#131; metadata-only adapter registration no longer counts as complete.
- Native decentralized protocol engine bundling is tracked under #133; user-installed protocol prerequisites are not acceptable as the default path.
- AFMarket A2A peer expert and embedded training surfaces are implemented in Swift, tested locally, pushed, and #113 is closed.

## Active Task

## Web Eval Harness Copy Revert

- [x] Confirm the parent repository still records the intended `web` submodule pointer.
- [x] Identify the accidental eval-harness copy as nested `web` commit `8229164` (`sync`).
- [x] Create GitHub issue for reverting the accidental `web` copy (#145).
- [x] Revert the accidental nested `web` commit without force-pushing history.
- [x] Verify focused web tests and hygiene locally; skip the web build per prior user direction because Lovable will handle it.
- [x] Commit and push the repaired nested `web` repository and parent submodule pointer/status.

Validation notes:

- Web build intentionally deferred per prior user direction on 2026-06-07.
- Nested `web` repository commit `273146b` reverts `8229164` and was pushed to `advatar/trustless-web-explorer`.
- `git diff --stat 06c296f62064de7643bf6b03b30dfb5a73afdd95..HEAD` in `web` reported no tree diff after the revert.
- `npm test` in `web` passed.
- `rg -n "contextweaver|EvalHarness|prune-eval|mock-agent|public/images/prune_tree|src/pages/Docs|src/pages/Strategy" .` in `web` reported no copied eval-harness remnants.

## Web Placeholder Cleanup

- [x] Re-scan the web app for user-visible placeholder, coming-soon, and demo copy.
- [x] Create GitHub issue for fixing the remaining web placeholders (#144).
- [x] Replace the hero blueprint coming-soon CTA with real navigation.
- [x] Remove or rename the agent illustration placeholder marker and delete unused placeholder assets.
- [x] Update demo wording to product/catalog wording and add tests preventing regressions.
- [x] Verify focused web tests, scoped lint, and hygiene locally; skip the web build per prior user direction because Lovable will handle it.
- [x] Commit and push only scoped changes.

Validation notes:

- `npm test` in `web` passed.
- `npx eslint src/components/Hero.tsx src/components/AgentsSection.tsx src/components/SolutionSection.tsx src/components/CallToAction.tsx tests/a2ui-deployment-content.test.mjs` in `web` passed.
- `git diff --check -- src/components/Hero.tsx src/components/AgentsSection.tsx src/components/SolutionSection.tsx src/components/CallToAction.tsx tests/a2ui-deployment-content.test.mjs public/placeholder.svg` in `web` passed.
- `LC_ALL=C grep -n '[^ -~]' src/components/Hero.tsx src/components/AgentsSection.tsx src/components/SolutionSection.tsx src/components/CallToAction.tsx tests/a2ui-deployment-content.test.mjs || true` in `web` reported no non-ASCII matches.
- Placeholder scan now reports only regression-test assertions and shadcn `placeholder:` CSS utility classes.
- Web build intentionally deferred per prior user direction on 2026-06-07.
- Nested `web` repository commit `06c296f` was pushed to `advatar/trustless-web-explorer`.

## Web Landing Page Subpage Navigation

- [x] Assess the current web router, navigation, landing page composition, and existing capabilities/architecture pages.
- [x] Create GitHub issue for splitting the long landing page into logical subpages (#143).
- [x] Restructure the landing page into a concise overview and move detailed feature surfaces to dedicated routes.
- [x] Update desktop and mobile navigation so users can reach each logical subpage directly.
- [x] Add or update focused web content tests for the route split and navigation.
- [x] Verify focused web tests and hygiene locally; skip the web build per prior user direction because Lovable will handle it.
- [x] Commit and push only scoped changes.

Validation notes:

- `npm test` in `web` passed.
- `npx eslint src/App.tsx src/pages/Index.tsx src/pages/Capabilities.tsx src/pages/Architecture.tsx src/pages/Agents.tsx src/pages/Wallet.tsx src/pages/Protocols.tsx src/pages/Comparison.tsx src/components/Navbar.tsx src/components/MobileStickyBar.tsx src/components/Hero.tsx src/components/ExploreSurfacesSection.tsx` in `web` passed.
- `git diff --check -- src/App.tsx src/pages/Index.tsx src/pages/Capabilities.tsx src/pages/Architecture.tsx src/pages/Agents.tsx src/pages/Wallet.tsx src/pages/Protocols.tsx src/pages/Comparison.tsx src/components/Navbar.tsx src/components/MobileStickyBar.tsx src/components/Hero.tsx src/components/ExploreSurfacesSection.tsx tests/a2ui-deployment-content.test.mjs` in `web` passed.
- `LC_ALL=C grep -n '[^ -~]' src/App.tsx src/pages/Index.tsx src/pages/Capabilities.tsx src/pages/Architecture.tsx src/pages/Agents.tsx src/pages/Wallet.tsx src/pages/Protocols.tsx src/pages/Comparison.tsx src/components/Navbar.tsx src/components/MobileStickyBar.tsx src/components/Hero.tsx src/components/ExploreSurfacesSection.tsx tests/a2ui-deployment-content.test.mjs || true` in `web` reported no non-ASCII matches.
- Web build intentionally deferred per prior user direction on 2026-06-07.
- Nested `web` repository commit `9f6cae7` was pushed to `advatar/trustless-web-explorer`.

## Web Landing Page Feature Advertising

- [x] Assess the current web landing page against the current Swift/browser, wallet, EUDI, payments, AFMarket, A2UI, memory, and workflow feature inventory.
- [x] Create GitHub issue for advertising the full dBrowser feature set on the landing page (#142).
- [x] Refresh the landing page content so it describes and promotes the full product surface without collapsing human and agent wallet security domains.
- [x] Add or update focused web content tests for the advertised feature inventory.
- [x] Verify focused web tests and hygiene locally; skip the web build per user direction because Lovable will handle it.
- [x] Commit and push only scoped changes.

Validation notes:

- `npm test` in `web` passed.
- `git diff --check -- src/pages/Index.tsx src/components/Hero.tsx src/components/FeatureInventorySection.tsx src/components/WalletControlPlaneSection.tsx src/components/CallToAction.tsx tests/a2ui-deployment-content.test.mjs` in `web` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md web/src/pages/Index.tsx web/src/components/Hero.tsx web/src/components/FeatureInventorySection.tsx web/src/components/WalletControlPlaneSection.tsx web/src/components/CallToAction.tsx web/tests/a2ui-deployment-content.test.mjs || true` reported no non-ASCII matches.
- `npm run lint` in `web` still fails on pre-existing shadcn/Tailwind files not touched by this task: `src/components/ui/command.tsx`, `src/components/ui/textarea.tsx`, and `tailwind.config.ts`, plus existing fast-refresh warnings.
- Web build intentionally deferred per user direction on 2026-06-07.
- Nested `web` repository commit `e3525a5` was pushed to `advatar/trustless-web-explorer`.

## EUDI Agent Identity Issuance And Verified Email

- [x] Assess the current Swift EUDI wallet/control-plane foundation and the local `cliwallet` verified email VC format.
- [x] Create GitHub issue for completing EUDI agent identity issuance and verified email credential import (#141).
- [x] Add Swift models for importing `EmailAddressCredential` verified email VCs into the human wallet.
- [x] Add scoped agent identity issuance so child agent principals receive derived identity credentials and receipts, not root human credentials.
- [x] Surface verified email and delegated agent identity state in the wallet control-plane UI.
- [x] Add focused Swift unit tests for email VC import, successful delegated agent identity issuance, missing-grant denial, revocation denial, and runtime/UI state.
- [x] Verify focused Swift tests, hygiene, and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped changes.

Validation notes:

- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-eudi-agent-identity-tests -only-testing:dBrowserTests/eudiEmailCredentialImporterAcceptsCliwalletVerifiedEmailForHumanWallet -only-testing:dBrowserTests/eudiWalletIdentityIssuerIssuesScopedVerifiedEmailToAgent -only-testing:dBrowserTests/eudiWalletIdentityIssuerDeniesMissingOrRevokedVerifiedEmailGrant -only-testing:dBrowserTests/walletControlPlaneSurfacesVerifiedEmailAndAgentIdentityCredentials -only-testing:dBrowserTests/runtimeBridgeSurfacesWalletControlPlanePrincipalsAndGrants` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-eudi-agent-identity-build` passed.
- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift || true` reported only existing author-name comments in Swift files.

## Unified Wallet Control Plane And Agent Principals

- [x] Assess the current Swift wallet, EUDI, and agentic payments foundation.
- [x] Create GitHub issue for the unified wallet control plane and isolated agent principals (#140).
- [x] Add Swift models for human and agent wallet principals, agent wallet profiles, delegated capabilities, grants, revocation, and wallet receipts.
- [x] Enforce policy boundaries so agents receive scoped identity/payment/crypto capabilities rather than root human credentials, raw payment instruments, or unrestricted signing authority.
- [x] Surface human wallets and agent wallets side by side in the Wallet panel with visible delegation chains, capability vaults, grants, and receipts.
- [x] Add focused Swift unit tests for principal isolation, grant budgets, protocol scopes, revocation, and runtime/UI state.
- [x] Verify focused Swift tests, hygiene, and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped changes.

Validation notes:

- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-wallet-control-plane-tests -only-testing:dBrowserTests/walletControlPlaneSeparatesHumanRootAndAgentChildVaults -only-testing:dBrowserTests/walletControlPlaneGrantBudgetsProtocolsAndRevocationAreEnforced -only-testing:dBrowserTests/walletControlPlaneReceiptsExposeSelectiveProofsAndDelegatedTokensOnly -only-testing:dBrowserTests/runtimeBridgeSurfacesWalletControlPlanePrincipalsAndGrants` passed.
- A focused regression lane passed with `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-wallet-control-plane-tests` and `-only-testing` filters for wallet control-plane, EUDI/payment, AP2/ACP/x402/TAP, and wallet explorer policy tests.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-wallet-control-plane-build` passed.
- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/WalletExplorer.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/WalletExplorer.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift || true` reported only existing author-name comments in Swift files.

## Swift EUDI Wallet And Agentic Payments Foundation

- [x] Re-check official Visa Trusted Agent Protocol, OpenAI/Stripe ACP, EUDI Wallet Kit, and related payment protocol sources.
- [x] Create GitHub issue for implementing the Swift EUDI Wallet and agentic payments foundation (#139).
- [x] Add Swift models for EUDI credential presentation, Visa Trusted Agent Protocol, ACP checkout, AP2 mandates, x402 payments, Notabene TAP transfer authorization, and payment receipts.
- [x] Add policy engine fixtures that prevent models from spending or disclosing identity without typed approval.
- [x] Surface EUDI/payment capabilities in the wallet/advantage architecture without claiming provider certification.
- [x] Add focused Swift unit tests for identity disclosure, trusted-agent signatures, ACP checkout, mandate binding, x402, TAP, recurrence, revocation, and receipts.
- [x] Verify focused Swift tests, hygiene, and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped changes.

Validation notes:

- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-eudi-agentic-payments-tests -only-testing:dBrowserTests/eudiWalletPresentationRequiresStepUpAndMinimizesDisclosure -only-testing:dBrowserTests/visaTrustedAgentVerifierChecksKeysHeadersAlgorithmsAndPaymentContext -only-testing:dBrowserTests/acpCheckoutBindsBasketAndDoesNotStoreRawPaymentCredentials -only-testing:dBrowserTests/agenticPaymentPolicyRequiresUserApprovalBeforeReceiptApproval -only-testing:dBrowserTests/ap2MandatesMustIncludeIntentCartAndPaymentBinding -only-testing:dBrowserTests/x402AndNotabeneTransfersBindToIntentBeforeApproval -only-testing:dBrowserTests/advantagePanelIsTopLevelNavigationAndTracksStrawberryBaseline` passed.
- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md swift/dBrowser/dBrowser/AgenticPayments.swift swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift || true` produced only existing author-name comment matches in Swift files.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-eudi-agentic-payments-build` passed.

## Web3 AI Browser Strategy Refresh

- [x] Research current primary sources for EUDI Wallet reference implementation, AP2/A2P, TAP, ACP, x402, Mastercard Agent Pay, and related agentic payment rails.
- [x] Create GitHub issue for the Web3/AI browser strategy refresh and agentic payments plan (#138).
- [x] Refresh the Swift Strawberry survey so it reflects closed parity gaps and the new Web3/AI browser ambition.
- [x] Add a dedicated architecture section for EUDI Wallet and agentic payment protocol integration.
- [x] Verify Markdown hygiene and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped documentation changes.

Validation notes:

- `git diff --check -- STATUS.md STRAWBERRY_SWIFT.md docs/ARCHITECTURE.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md STRAWBERRY_SWIFT.md docs/ARCHITECTURE.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-web3-ai-strategy-build` passed.

## Swift Strawberry Gap Closure

- [x] Create GitHub issue for closing the remaining Swift Strawberry UX gaps (#137).
- [x] Add Swift models for browser import/switcher, companion onboarding, research source ledgers, recurring workflow automation, and Strawberry-style benchmark proof.
- [x] Update the Advantage scorecard so the former Strawberry gap areas are matched or exceeded with concrete Swift evidence.
- [x] Add focused Swift tests for the closed gap models and no-gap Advantage scorecard.
- [x] Verify focused Swift tests, hygiene, and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped changes.

Validation notes:

- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-strawberry-gap-closure-tests -only-testing:dBrowserTests/advantagePanelIsTopLevelNavigationAndTracksStrawberryBaseline -only-testing:dBrowserTests/browserImportPlannerSeparatesSafeDataFromSecrets -only-testing:dBrowserTests/companionOnboardingRecommendsAppsMemoryConnectorsModelsAndWorkflows -only-testing:dBrowserTests/researchLedgerExportsDatedCitationsMarkdownAndCSV -only-testing:dBrowserTests/recurringWorkflowAutomationHandlesSchedulesTriggersCooldownsAndNotifications -only-testing:dBrowserTests/strawberryBenchmarkSuiteSupportsTwelveTaskAndCredentialConstrainedRuns` passed.
- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- Changed-line non-ASCII scan passed for the scoped files.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-strawberry-gap-closure-build` passed.

## Local AFM Expert Training Marketplace

- [x] Create GitHub issue for local AFM expert training and marketplace build-out (#136).
- [x] Replace the placeholder `apps/afm-marketplace` target with a repo-owned local training and marketplace API.
- [x] Add deterministic local adapter/runner-pack artifact generation for embedded AFM expert training jobs.
- [x] Extend the Swift AFM service client/runtime bridge so marketplace-backed training jobs can be created, published, and surfaced as available runner packs and peer experts.
- [x] Add focused Node and Swift unit tests for training, marketplace publishing, snapshot decoding, and local fallback labeling.
- [x] Verify the marketplace package and Swift/Xcode test lanes locally.
- [ ] Commit and push only scoped changes.

Validation notes:

- `pnpm --filter @browser/afm-marketplace test` passed.
- `pnpm --filter @browser/afm-marketplace build` passed.
- `pnpm --filter @browser/afm-marketplace lint` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/dBrowser-local-afm-marketplace-tests -only-testing:dBrowserTests/afmExpertTrainingJobBuildsLocalPeerExpertContract -only-testing:dBrowserTests/runtimeBridgeCreatesEmbeddedAFMTrainingJobAndA2APreview -only-testing:dBrowserTests/afmServicesClientLoadsMarketplaceRunnerPacks -only-testing:dBrowserTests/afmServicesClientCreatesAndPublishesMarketplaceTrainingJob -only-testing:dBrowserTests/runtimeBridgePublishesLocalAFMTrainingJobIntoMarketplacePacks` passed.
- `git diff --check -- STATUS.md README.md docs/ARCHITECTURE.md apps/afm-marketplace/package.json apps/afm-marketplace/scripts/build.mjs apps/afm-marketplace/scripts/dev-server.mjs apps/afm-marketplace/scripts/lint.mjs apps/afm-marketplace/src/main.mjs apps/afm-marketplace/src/main.test.mjs swift/dBrowser/dBrowser/AFMExpertTraining.swift swift/dBrowser/dBrowser/AFMServicesClient.swift swift/dBrowser/dBrowser/BrowserViewModel.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -derivedDataPath /tmp/dBrowser-local-afm-marketplace-build` passed.

## Swift Strawberry Advantage Center

- [x] Create GitHub issue for adding an in-app Swift Advantage Center (#135).
- [x] Add Swift capability/advantage models that compare dBrowser against Strawberry's public baseline.
- [x] Add a top-level Advantage panel with score tiles, advantage groups, and action buttons into existing Swift UX.
- [x] Add focused Swift tests proving dBrowser exceeds Strawberry in tracked capabilities and surfaces gap actions.
- [x] Verify focused Swift tests, Markdown hygiene, and the macOS Swift/Xcode build locally.
- [x] Commit and push only scoped changes.

Validation notes:

- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests/panelSelectionShowsPanelsAndNavigationReturnsToBrowser -only-testing:dBrowserTests/walletPanelIsTopLevelNavigationAndSeparateSidebarSection -only-testing:dBrowserTests/advantagePanelIsTopLevelNavigationAndTracksStrawberryBaseline -only-testing:dBrowserTests/browserViewModelCanNavigateFromAdvantageActions` passed.
- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- Changed-line non-ASCII scan passed for the scoped files; the broader scan still reports existing accented author comments in Swift headers.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Swift Strawberry Survey Renewal

- [x] Create GitHub issue for renewing the Swift Strawberry parity survey (#134).
- [x] Re-check current public Strawberry Browser progress and cite the inspected sources.
- [x] Compare the renewed Strawberry baseline against the current Swift implementation state.
- [x] Update `STRAWBERRY_SWIFT.md` with closed gaps, remaining gaps, and a prioritized gap-closure plan.
- [x] Verify Markdown hygiene and the Swift/Xcode build locally.
- [x] Commit and push only scoped documentation changes.

Validation notes:

- `git diff --check -- STATUS.md STRAWBERRY_SWIFT.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md STRAWBERRY_SWIFT.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Native Protocol Engine Bundling Plan

- [x] Create a GitHub issue for bundling native decentralized protocol engines (#133).
- [x] Inspect the current Swift adapter states and local `services/storage-adapters` service boundary.
- [x] Confirm the product requirement that users must not install renterd, Storj uplink, Tahoe, Autonomi, Iroh, Hypercore, Radicle, Ceramic, OrbitDB/IPFS, torrent engines, or other protocol prerequisites themselves.
- [x] Capture the platform split between macOS bundled helper engines and iOS signed in-process Swift/native-framework engines.
- [x] Document the protocol-by-protocol bundling matrix, reproducible script layout, engine manager contract, and implementation phases.
- [x] Verify documentation hygiene and the Swift/Xcode build locally.
- [x] Commit and push only scoped files.

Validation notes:

- Created GitHub issue #133 and added the bundle-first product clarification as an issue comment.
- `git diff --check -- STATUS.md docs/NATIVE_PROTOCOL_ENGINE_BUNDLING_PLAN.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md docs/NATIVE_PROTOCOL_ENGINE_BUNDLING_PLAN.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Native Protocol Handler Service

- [x] Inspect existing Swift native adapter endpoints and local service workspace.
- [x] Add a repo-owned local storage adapter service that binds the Swift localhost adapter ports.
- [x] Implement protocol-specific handler contracts for Filecoin, Walrus, Iroh, Hypercore, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle.
- [x] Return verified handler metadata, redaction, backend requirements, and configured local-backend proxy targets per protocol.
- [x] Add service tests covering every protocol handler, invalid input handling, and credential-scoped backends.
- [x] Wire the service into workspace scripts and document local usage.
- [x] Verify service tests plus the Swift/Xcode build locally.
- [x] Commit and push only scoped files.

Validation notes:

- `pnpm --filter @browser/storage-adapters build` passed.
- `pnpm --filter @browser/storage-adapters lint` passed.
- `pnpm --filter @browser/storage-adapters test` passed.
- HTTP smoke passed against `127.0.0.1:4883/health` and `/dweb/iroh/native?...format=json`.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## Native Decentralized Storage Adapter Rollout

- [x] Inspect existing content-capable resolver state, local services, and package surfaces for reusable protocol engines.
- [x] Add a Swift native/local adapter configuration for every registered decentralized storage protocol.
- [x] Resolve supported protocol URIs through direct gateways or protocol-specific local endpoints before any configured remote resolver.
- [x] Keep unsupported locator forms explicit with per-protocol requirements instead of generic failures.
- [x] Add unit tests proving every registered protocol has a native/local adapter path and remote fallback remains opt-in.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

Validation notes:

- Focused decentralized storage Swift tests passed for direct gateways, native/local adapter routing, remote fallback, explicit resolver requirements, and view-model navigation handoffs.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## Vendored SwiftLM Local LLM Runtime

- [x] Create GitHub issue for vendoring SwiftLM local LLM functionality (#132).
- [x] Vendor the SwiftLM package that owns local model download, catalog, runtime, and control-plane behavior into this repo.
- [x] Repoint the dBrowser Xcode project from the sibling `../../../Packages/SwiftLM` checkout to the repo-local package.
- [x] Add focused tests proving the app uses the vendored package and still routes local LLM control-plane actions.
- [x] Verify the vendored Swift package and dBrowser Swift/Xcode build locally.
- [x] Commit and push only scoped files from the worktree.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser.xcodeproj/project.pbxproj swift/dBrowser/dBrowserTests/dBrowserTests.swift swift/Packages/SwiftLM` passed.
- `swift test --package-path swift/Packages/SwiftLM` passed; it emitted an existing `String(contentsOf:)` deprecation warning in the copied SwiftLM `Storage.swift`.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed after removing the stale project comment that still named the sibling SwiftLM path.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## Content-Capable Decentralized Protocol Resolution

- [x] Create GitHub issue for correcting metadata-only protocol registrations (#131).
- [x] Inspect current Swift resolver behavior and the local `./services` surface for reusable storage resolvers.
- [x] Add a typed content resolver contract that distinguishes loadable content from adapter metadata.
- [x] Make supported decentralized storage protocols report content-loading requirements without generic placeholders.
- [x] Add focused Swift tests across every registered scheme.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- Focused decentralized content resolver tests passed with `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests/decentralizedStorageRegistryCoversAppDistributionNetworks -only-testing:dBrowserTests/decentralizedStorageAdaptersTrackNativeProtocolIssues -only-testing:dBrowserTests/decentralizedStorageContentResolutionDistinguishesLoadableBytesFromResolverRequirements -only-testing:dBrowserTests/decentralizedProtocolExplanationKeepsLightClientsAsTrustRoot -only-testing:dBrowserTests/runtimeBridgeResolvesDecentralizedAddresses -only-testing:dBrowserTests/runtimeBridgeHandlesEveryDecentralizedStorageNetwork -only-testing:dBrowserTests/runtimeBridgeRemoteResolverHandlesEveryStorageSchemeAlias -only-testing:dBrowserTests/runtimeBridgeReportsResolverRequirementWhenNoStorageResolverIsConfigured -only-testing:dBrowserTests/runtimeBridgeNamesResolverRequirementsForNonGatewayStorageProtocols -only-testing:dBrowserTests/viewModelLoadsRemoteStorageResolverHandoffs`.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed after rerun; the first concurrent run failed because Xcode locked the shared build database while the macOS build was running.

## Issue Closure And Resolver Honesty

- [x] Inspect open GitHub issues and current resolver implementation for work that is actually handleable in-app.
- [x] Remove the hardcoded assumption that decentralized storage resolves through `https://zerok.cloud`.
- [x] Keep ZeroK documented only as the zero-knowledge/LLM gateway surface, not as an unverified storage resolver.
- [x] Reclassify storage protocols without native mobile implementations as explicit adapter-required states unless a real storage resolver is configured.
- [x] Leave protocol issues that require real external stacks, backends, or product decisions open with explicit blockers.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/LLMConversation.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests/decentralizedStorageRegistryCoversAppDistributionNetworks -only-testing:dBrowserTests/decentralizedStorageAdaptersTrackNativeProtocolIssues -only-testing:dBrowserTests/decentralizedProtocolExplanationKeepsLightClientsAsTrustRoot -only-testing:dBrowserTests/runtimeBridgeResolvesDecentralizedAddresses -only-testing:dBrowserTests/runtimeBridgeHandlesEveryDecentralizedStorageNetwork -only-testing:dBrowserTests/runtimeBridgeRemoteResolverHandlesEveryStorageSchemeAlias -only-testing:dBrowserTests/runtimeBridgeReportsAdapterRequiredWhenNoStorageResolverIsConfigured -only-testing:dBrowserTests/viewModelLoadsRemoteStorageResolverHandoffs -only-testing:dBrowserTests/llmContextRendererCarriesPruneAndSwiftLMMinimizationState` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## Native Decentralized Protocol Adapter Rollout

- [x] Reopen the decentralized storage and LLM context issues as active implementation work.
- [x] Add protocol-by-protocol adapter metadata for Filecoin, Walrus, Iroh, Hypercore, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle.
- [x] Teach the runtime bridge to emit adapter-specific resolver handoffs instead of a single generic remote route.
- [x] Add tests proving every protocol adapter preserves its locator, route, trust boundary, and issue tracking link.
- [x] Fold Prune and SwiftLM into the active context-minimization work so #115 has executable app state, not just planning text.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowser/LLMConversation.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests/decentralizedStorageRegistryCoversAppDistributionNetworks -only-testing:dBrowserTests/decentralizedStorageAdaptersTrackNativeProtocolIssues -only-testing:dBrowserTests/decentralizedProtocolExplanationKeepsLightClientsAsTrustRoot -only-testing:dBrowserTests/runtimeBridgeResolvesDecentralizedAddresses -only-testing:dBrowserTests/runtimeBridgeHandlesEveryDecentralizedStorageNetwork -only-testing:dBrowserTests/runtimeBridgeRemoteResolverHandlesEveryStorageSchemeAlias -only-testing:dBrowserTests/runtimeBridgeCanStillReportResolverRequiredWhenRemoteRuntimeIsDisabled -only-testing:dBrowserTests/viewModelLoadsRemoteStorageResolverHandoffs -only-testing:dBrowserTests/llmContextRendererCarriesPruneAndSwiftLMMinimizationState -only-testing:dBrowserTests/llmConversationRendererCompressesWithoutMutatingLedger` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## Decentralized Storage Resolver Gap Closure

- [x] Create GitHub issues for the overall resolver roadmap and each missing storage protocol.
- [x] Add a protocol-specific resolver adapter contract for storage networks that lack direct mobile gateways.
- [x] Implement remote resolver handoff URLs for Filecoin, Walrus, Iroh, Hypercore, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle.
- [x] Update runtime explanations so the app no longer claims these protocols only stop at resolver-required placeholders.
- [x] Add focused unit tests proving each protocol resolves to gateway or remote-runtime handoff behavior.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/BrowserModels.swift swift/dBrowser/dBrowser/RuntimeBridge.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'generic/platform=iOS Simulator'` passed.

## SwiftLM Local LLM Management

- [x] Inspect ../SwiftLM and ../Packages/SwiftLM integration points.
- [x] Link the dBrowser Swift app to the local SwiftLM package products.
- [x] Add a Local LLMs management model and panel for SwiftLM control-plane operations.
- [x] Add unit tests covering the package-backed local LLM management surface.
- [x] Verify the Swift/Xcode build and focused test lane locally.
- [x] Commit and push only scoped files.

## Full Decentralized Protocol Handling

- [x] Inspect current decentralized URI registry, runtime bridge, and browser fallback behavior.
- [x] Add explicit runtime handling state for recognized protocols that still need native or remote resolvers.
- [x] Extend resolver/runtime tests across every registered protocol and scheme alias.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## A2UI App Store Preview Feedback

- [x] Inspect the current Swift A2UI App Store preview button path.
- [x] Create a GitHub issue with the bug details and implementation plan (#117).
- [x] Add first-class preview state for App Store listings.
- [x] Make Preview visibly select the listing and focus the rendered app preview.
- [x] Add focused tests for preview state transitions.
- [x] Verify the Swift/Xcode build and focused unit test lane locally.
- [x] Commit and push only the scoped files.

Validation notes:

- `git diff --check -- STATUS.md swift/dBrowser/dBrowser/ContentView.swift swift/dBrowser/dBrowser/A2UITokenRenderer.swift swift/dBrowser/dBrowserTests/dBrowserTests.swift` passed.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.
- `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS' -only-testing:dBrowserTests` passed.
- Full `xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` is still blocked by existing `dBrowserUITests` failures around app termination, gateway text lookup, IPFS swipe hit point, and missing panel button accessibility; `dBrowserTests` passed within that run.

## External LLM Context Efficiency Plan

- [x] Inspect `../Prune` context engine docs, Swift language-pack notes, MCP/CLI surfaces, and packing strategy features.
- [x] Inspect `/Users/johansellstrom/dev/advatar/SwiftLM` README, package products, control-plane client, local API, and model/runtime contracts.
- [x] Create a GitHub issue with detailed integration plans for Prune and SwiftLM to reduce external LLM usage (#115).
- [x] Capture the recommended app boundary for context packing, local runtime routing, model switching, and provider exposure labels.
- [x] Verify the status-only change locally.
- [x] Commit and push only the scoped status update.

Validation notes:

- `git diff --check -- STATUS.md` passed.
- `LC_ALL=C grep -n '[^ -~]' STATUS.md || true` produced no non-ASCII matches.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Deprecated Documentation Cleanup

- [x] Inventory root-level Markdown and narrative docs for current Swift relevance.
- [x] Create a GitHub issue for archiving/removing deprecated Rust/Tauri documents (#114).
- [x] Move deprecated Rust/Tauri documents into `archive/` and leave current Swift docs in place.
- [x] Update current documentation references so they do not point at archived validation/plans as active guidance.
- [x] Verify Markdown hygiene and the Swift/Xcode build locally.
- [x] Commit and push only the scoped documentation cleanup.

Validation notes:

- `git diff --check` passed.
- Live-doc reference scan found no active pointers to removed root validation/plans, aside from intentional historical status entries.
- `xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'` passed.

## Universal Decentralized URI Resolution

- [x] Inspect current Swift URL resolver, runtime bridge, and decentralized protocol tests.
- [x] Add a decentralized storage URI registry for app/data distribution networks.
- [x] Delegate all recognized storage URIs to the runtime bridge instead of search fallback.
- [x] Add focused unit tests for known and unknown URI schemes.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Web A2UI Logos Aztec Deployment Copy

- [x] Inspect existing website A2UI/App Store messaging and current Swift catalog support.
- [x] Add specific website copy for Swift A2UI App Store install/open/preview behavior.
- [x] Explain Logos Basecamp deployment support for A2UI apps.
- [x] Explain Aztec deployment support for A2UI apps.
- [x] Add or update focused web tests for the new website claims.
- [x] Verify the web content test and production build locally; lint remains blocked by existing UI/tailwind lint errors.
- [x] Commit and push only scoped files.

## Swift A2UI App Store

- [x] Inspect the current Swift A2UI debug panel and existing app catalog references.
- [x] Add an A2UI app catalog model with install state.
- [x] Surface an App Store section above the token debug renderer.
- [x] Add install/open behavior that renders each app's A2UI preview.
- [x] Add focused unit tests for catalog metadata and install state.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Swift A2UI Aztec Protocol

- [x] Inspect Aztec docs, network page, AI tooling, PXE, and monorepo for current protocol wording.
- [x] Add an Aztec Network protocol profile for A2UI apps.
- [x] Surface Aztec as a selectable A2UI app runtime/protocol profile in the Swift panel.
- [x] Add Aztec runtime status and explanations to the runtime grid.
- [x] Add focused unit tests for the Aztec A2UI protocol offering.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## Swift A2UI Logos Runtime

- [x] Inspect Logos Basecamp and Logos docs for current runtime/module wording.
- [x] Add a Logos Basecamp runtime profile for A2UI apps.
- [x] Surface Logos as a selectable A2UI app runtime in the Swift panel.
- [x] Add Logos runtime status and explanations to the runtime grid.
- [x] Add focused unit tests for the Logos A2UI runtime offering.
- [x] Verify the Swift/Xcode build and test lane locally.
- [x] Commit and push only scoped files.

## AFMarket A2A Expert Training

- [x] Create tracker issue for AFMarket A2A expert marketplace and embedded expert training (#113).
- [x] Inspect Swift AFMarket service, router, registry, node, Copilot, and panel surfaces.
- [x] Add typed Swift models for peer AFM experts, A2A calls, embedded training jobs, fine-tune policy, and publish readiness.
- [x] Extend runtime bridge/view model with local training job creation and A2A peer expert call previews/results.
- [x] Surface AFMarket peer experts and embedded training jobs in the Swift AFM services panel.
- [x] Add focused Swift tests for contracts, lifecycle, and safe fallback labeling.
- [x] Verify the Swift test lane locally.
- [x] Commit and push only scoped files.
- [x] Update and close GitHub issue #113.

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
