# Swift Strawberry Parity And Web3 AI Browser Strategy

Renewed: 2026-06-06
Trackers:

- Survey renewal: https://github.com/advatar/Browser/issues/134
- Closed Swift UX gaps: https://github.com/advatar/Browser/issues/137
- Web3 AI browser and agentic payments plan: https://github.com/advatar/Browser/issues/138

This survey keeps the Swift app at or above Strawberry Browser in browser-agent
features and user experience. The original "missing primitives" plan is closed:
the Swift app now tracks all 12 public Strawberry baseline areas, reports zero
scorecard gaps, and has focused tests for the closed UX models.

Strawberry is now a comparison baseline, not the ceiling. The next strategy is
to make dBrowser the Web3 and AI browser to beat: a native browser that combines
page automation, local-first model choice, governed memory, AFMarket execution,
A2UI apps, EUDI Wallet identity, approval-gated wallet policy, chain trust, and
agentic payment protocols under one auditable user-control surface.

## Leadership Goal

Keep Strawberry parity as a permanent baseline while pushing beyond it on
capabilities users can feel:

- The assistant can understand the current page and relevant browser context.
- The assistant can research, cite, compare, and export structured work.
- The assistant can click, type, scroll, navigate, submit, and wait on real pages
  through audited, approval-gated automation.
- Workflows can be saved, repeated, scheduled, monitored, stopped, and audited.
- Users can connect external apps and MCP servers without unsafe credential
  handling.
- Regular browsing is free, AI work is metered transparently, and users can see
  what ran, what it cost, and what data left the device.
- The browser remains a strong browser first: import, tabs, history, bookmarks,
  downloads, default-browser ergonomics, and cross-platform availability matter.
- Identity, wallet, and payments are first-class browser capabilities: an agent
  may propose a transaction, but only typed policy, verified identity, explicit
  approval, and auditable receipts can authorize one.

dBrowser should also keep its differentiators visible: local MLX/SwiftLM model
paths, context-preserving model switching, governed OpenMind memory, AFMarket
runner packs, A2UI apps, decentralized protocol handling, wallet capabilities,
chain-trust verification, EUDI Wallet credential presentation, AP2 mandates,
ACP checkout, x402 machine payments, Visa Trusted Agent Protocol, Notabene TAP,
and Mastercard Agent Pay style network-token flows.

## Public Strawberry Progress Checked

Sources inspected on 2026-06-05:

- Homepage and FAQ: https://strawberrybrowser.com/
- Getting-started use case: https://strawberrybrowser.com/use-cases/getting-started
- What Strawberry is: https://strawberrybrowser.com/tutorials/getting-started/what-strawberry-is
- Think With You: https://strawberrybrowser.com/tutorials/features/think-with-you
- Research For You: https://strawberrybrowser.com/tutorials/features/research-for-you
- Act For You: https://strawberrybrowser.com/tutorials/features/act-for-you
- Work While You Are Away: https://strawberrybrowser.com/tutorials/features/work-while-away
- Companion integrations: https://strawberrybrowser.com/tutorials/integrations/companion-integrations
- MCP tutorial: https://strawberrybrowser.com/tutorials/integrations/mcp
- Security page: https://strawberrybrowser.com/security
- Pricing page: https://strawberrybrowser.com/pricing
- Benchmark results: https://strawberrybrowser.com/benchmarks/strawberry-vs-competition
- Benchmark specification: https://strawberrybrowser.com/benchmarks/spec
- Open-beta coverage: https://www.computerworld.com/article/4133392/swedish-ai-browser-strawberry-now-available-to-everyone.html

Observed Strawberry baseline:

- Strawberry is publicly marketed as an open beta after closed testing, with
  macOS and Windows availability.
- It is positioned around browser work for sales, talent, founders/operators,
  marketing, data extraction, and research teams.
- Onboarding now maps role, connected apps, and day-to-day work, then sets up a
  personalized companion and suggests workflows.
- Browser switching is part of the pitch: import passwords, bookmarks, and
  history from Chrome, Safari, Firefox, Edge, Arc, and Brave; use alongside the
  current browser if desired.
- Companions claim page context, page structure, conversation memory, and other
  open-tab context when relevant.
- Research claims include multi-source browsing, parallel research threads,
  synthesis, dated/source-linked output, and structured comparison.
- Agent mode claims real page actions: click, fill forms, scroll, navigate,
  select options, submit information, download files, and perform end-to-end
  multi-step tasks.
- Workflow claims include saving repeatable tasks, one-click reruns, scheduled
  runs, triggers based on site visits, page changes, notifications, or content
  appearing/disappearing, and monitoring while the user is away.
- Integration claims include Google Workspace, Microsoft 365, Slack, Notion,
  CRM platforms, calendar, notes, email, and MCP server connections.
- Safety claims include approval for important/protected/permanent actions,
  activity history, stop/takeover, locally stored chats/passwords/history/cookies,
  OAuth revocation, and prompt-injection mitigation.
- Smart History is described as disabled by default; when enabled, browsing
  activity is summarized by an AI partner and summaries are stored locally.
- Credit claims are clear: regular browsing is free, credits are used when
  companions chat or browse, and public plans range from free to full-time tiers.
- Strawberry publishes a 12-workflow benchmark spec and claims 99.2/100 across
  the suite, 43 minutes total runtime, Comet at 90.8, Atlas at 73.3, and about
  78 percent on GAIA.

## Current dBrowser Swift Evidence

The Swift app has closed the original low-level Strawberry gap list:

- `swift/dBrowser/dBrowser/BrowserWebView.swift` has a real `WKWebView` wrapper
  with typed automation request handling, tab scoping, timeouts, audited scripts,
  DOM query, page snapshot, and page action execution.
- `swift/dBrowser/dBrowser/StrawberryModels.swift` defines automation commands,
  bounded DOM records, page snapshots, approval reasons, Copilot run state,
  credit usage, saved workflows, workflow persistence, and Smart History storage.
- `swift/dBrowser/dBrowser/BrowserViewModel.swift` owns Copilot runs, page
  snapshot requests, workflow execution, cancellation on navigation/tab close,
  Smart History recall, OpenMind recall/writeback/correction, AFMarket routing,
  LLM router routing, and chain-trust snapshot refresh.
- `swift/dBrowser/dBrowser/ContentView.swift` has a native Copilot conversation
  surface with model selection, transcript, page snapshot controls, Stop, usage
  display, OpenMind memory controls, saved workflows, MCP server setup, local LLM
  management, chain trust, AFMarket services, and A2UI app surfaces.
- `swift/dBrowser/dBrowser/LLMConversation.swift` stores a provider-neutral
  conversation ledger, model-switch events, per-message model identity, page
  snapshot attachments, memory citations, context compression, local MLX, LLM
  router, AFMarket, and LLM Gateway model profiles.
- `swift/dBrowser/dBrowser/BrowserModels.swift` now contains the no-gap
  Advantage scorecard plus browser import/switcher planning, companion
  onboarding recommendations, research source ledgers, recurring workflow
  automation plans, and a Strawberry-compatible 12-task benchmark suite with
  credential-constrained 9-task mode.
- `swift/dBrowser/dBrowser/MCPServers.swift` supports editable HTTP, WebSocket,
  and stdio MCP server profiles with discovered tool state.
- `swift/dBrowser/dBrowser/OpenMindMemoryClient.swift` implements governed
  personal-memory access, step-up requests, evidence bundles, writeback,
  corrections, direct HTTP, and JSON-RPC MCP negotiation.
- `swift/dBrowser/dBrowser/AFMServicesClient.swift` covers runner packs,
  registry bundles, routing, leases, node install, attested runs, proof state,
  settlement state, verification checks, and service snapshots.
- `swift/dBrowser/dBrowser/*LightClient.swift`,
  `ChainTrustRegistry.swift`, `WalletExplorer.swift`, and
  `BlockchainCapabilityContracts.swift` give dBrowser chain and wallet
  capabilities that Strawberry does not publicly claim.
- `swift/dBrowser/dBrowserTests/dBrowserTests.swift` covers the core Swift
  primitives: URL resolution, runtime features, automation contracts, Copilot
  runs, cancellation, workflows, Smart History, MCP, OpenMind, AFMarket, LLM
  conversation persistence/model switching, local LLM management, wallet, and
  chain-trust behavior. The focused Strawberry lane also asserts 12/12 tracked
  baseline coverage and `gapCount == 0`.

## Closed Parity Matrix

| Area | Strawberry 2026 public baseline | dBrowser Swift state | Next leadership work |
| --- | --- | --- | --- |
| Distribution | Open beta for macOS and Windows. | Native Swift app targets Apple platforms and matches the baseline for the current product boundary. | Decide whether a Windows shell is a product goal or document the Apple-native trade. |
| Browser switching | Imports passwords, bookmarks, and history from major browsers and can run alongside them. | `BrowserImportPlanner` separates safe bookmark/history import from explicit password/cookie approval flows. | Build the first-run UI and platform-specific import adapters. |
| Companion onboarding | Role/app/workflow onboarding creates a personalized companion. | `BrowserCompanionOnboardingEngine` maps role, tools, recurring work, privacy posture, and model preference into recommendations. | Promote onboarding into the first-launch flow. |
| Page context | Current page, structure, conversation memory, and other tabs when relevant. | Active-page snapshots, bounded DOM extraction, transcript ledger, memory citations, and redaction are implemented. | Add relevance-ranked multi-tab context and video/transcript support. |
| Research | Parallel research, multi-source synthesis, dated/source-linked outputs. | `BrowserResearchLedger` records dated citations, evidence, confidence, markdown export, and CSV export. | Add planner-driven parallel tab/run orchestration. |
| Page actions | Click, fill, scroll, navigate, select, submit, download, and end-to-end workflows. | Typed click, type, focus, submit, scroll, navigate, wait, and stop run through audited `WKWebView` automation. | Expand select/menu/download/new-tab/upload coverage with fixture-backed UI tests. |
| Workflows | Save, rerun, schedule, trigger, monitor changes, and notify. | `BrowserRecurringWorkflowAutomation` models schedules, triggers, cooldowns, notifications, and approval-preserving policy. | Wire production scheduler execution and notification delivery. |
| Integrations | Built-in app integrations plus MCP. | MCP, A2UI, AFMarket, OpenMind, wallet capability contracts, and local marketplace surfaces exceed the baseline. | Harden OAuth connectors, credential storage, revocation, and app catalog UX. |
| Safety | Approval before important actions, stop/takeover, activity history. | dBrowser gates form submit, credentials, cross-origin navigation, destructive clicks, downloads, wallet/signing, and cancels on takeover. | Add policy presets, longer-lived audit history, and user-visible risk explanations. |
| Privacy | Local chats/passwords/history/cookies, Smart History disabled by default. | Local stores, redacted snapshots, governed OpenMind citations, and context commitments exceed the baseline. | Ship explicit Smart History modes and per-run data-egress receipts. |
| Credits | Browsing is free; credits only for companion chat/browsing. | Browser operations are zero-cost and model/provider usage is recorded per run. | Pass through exact provider usage and add plan/balance receipts. |
| Benchmarks | Publishes 12-workflow spec and claimed scores. | `StrawberryBenchmarkSuite` models B1-B12 plus 9-task credential-constrained mode and report artifacts. | Build the runnable public benchmark lane and publish fixtures. |
| Web3 trust | Strawberry does not publicly claim decentralized protocol loading, chain verification, or wallet policy receipts. | dBrowser has wallet/explorer coverage, chain-trust registries, A2UI wallet policy apps, AFMarket proof/settlement state, and decentralized protocol plans. | Bundle native protocol engines and unify proof, identity, wallet, and payment receipts. |
| AI execution | Strawberry focuses on companions. | dBrowser combines local MLX/SwiftLM, model switching, LLM Router, AFMarket, OpenMind memory, MCP, and A2UI native app surfaces. | Make run modes, trust/cost/performance tradeoffs, and agentic payment boundaries headline UX. |

## Historical Issue Map

Original Strawberry steps are no longer all open gaps. Keep this map for
traceability:

- #50 through #53: `WKWebView` automation bridge, DOM query, actions, and page
  snapshots. Implemented through the Swift Strawberry primitives and tracked in
  STATUS under the Swift Strawberry Open Issues Build.
- #54 through #58: Copilot activity/cancellation, credit accounting, saved
  workflows, concurrent runs, and Smart History. Implemented as Swift run,
  workflow, and history foundations.
- #69: AFMarket integration. Implemented across service-backed slices, with
  marketplace packs, routing, node/attestation/settlement, proof reporting, A2A
  experts, and training surfaces.
- #70: BrIAn/OpenMind memory. Implemented across governed recall, evidence
  bundle, step-up, writeback, correction, transport negotiation, and UI slices.
- #72: LLM conversation and model switching. Implemented across persistent
  conversations, model switch events, context rendering, router service adapter,
  local SwiftLM, and provider labels.
- #59 through #68: chain trust and major-chain foundations. Implemented through
  shared registry and Bitcoin, EVM, Solana, Cosmos, Substrate, Avalanche, TRON,
  XRPL, Sui, and Aptos slices.
- #133 remains active for native decentralized protocol engine bundling; it is a
  dBrowser differentiator rather than a Strawberry parity requirement.

## Leadership Roadmap After Parity

### P0 - Prove And Package The Baseline

1. Ship the runnable dBrowser benchmark lane.
   - Use `StrawberryBenchmarkSuite` as the B1-B12 source of truth.
   - Persist markdown, CSV, score, blocker, duration, and credential-mode
     artifacts under a repo-owned validation path.
   - Keep 9-task public mode separate from 12-task credentialed mode.

2. Promote the closed gap models into product UX.
   - First-run switcher/import flow.
   - Companion onboarding.
   - Research source ledger export.
   - Recurring workflow scheduler and notification surfaces.

3. Refresh public positioning.
   - Treat Strawberry parity as a tested baseline.
   - Lead with local-first model choice, A2UI apps, AFMarket proof execution,
     governed memory, chain trust, wallet policy, and agentic payment safety.

### P1 - Make Web3 And Agentic Payments Native

4. Implement the EUDI Wallet and agentic payments plan in
   `docs/ARCHITECTURE.md`.
   - EUDI Wallet adapters for credential presentation, OpenID4VCI/OpenID4VP,
     ISO 18013-5, SD-JWT VC, pseudonyms, and strong user authentication use
     cases.
   - AP2 mandate models for intent, cart, payment, hashes, signatures, expiry,
     budget, and revocation.
   - ACP checkout adapters for agent-presented commerce flows.
   - x402 buyer/server/facilitator models for API and content micropayments.
   - Visa Trusted Agent Protocol support for agent recognition signatures.
   - Notabene TAP support for blockchain transfer requests and encrypted
     pre-settlement authorization.
   - Mastercard Agent Pay style network-token and verifiable-intent policy
     abstractions.

5. Build one approval and receipt surface.
   - Bind page snapshot, cart hash, mandate hash, wallet/account, identity
     credential, chain/network, merchant/counterparty, model, tool, and user
     approval into a local receipt.
   - Make revocation, recurring budgets, cooldowns, and failure backoff visible.
   - Never let a model directly spend, sign, submit, or broadcast.

### P2 - Turn The Advantage Into A Product System

6. Promote A2UI apps into installable agent templates for research, shopping,
   operations, recruiting, sales, extraction, travel, forms, monitoring, wallet
   policy, and dweb publishing.

7. Make local-first model switching a headline control.
   - Present local MLX, SwiftLM, LLM Router, AFMarket, and LLM Gateway choices
     as a trust, cost, latency, and proof control.
   - Keep context continuity, compression, and model-switch events visible.

8. Keep decentralized and chain trust advantages visible everywhere money or
   identity moves.
   - Tie protocol loading, EUDI credential presentation, wallet actions, AP2,
     ACP, x402, TAP, AFMarket settlement, and chain-trust state into one evidence
     model.
   - Show verified, proof-checked, RPC fallback, mock, unavailable, and revoked
     states as distinct UI states.

9. Decide Windows parity explicitly.
   - If "at or above Strawberry" requires Windows, create a separate shell plan.
   - If Windows is not a product goal, document the trade: macOS/iOS native
     integration plus local MLX, wallet, identity, A2UI, and decentralized
     capabilities.

## Verification Baseline

For this documentation and strategy refresh:

- Run Markdown hygiene checks on `STATUS.md`, `STRAWBERRY_SWIFT.md`, and
  `docs/ARCHITECTURE.md`.
- Run a local Swift/Xcode build to prove the project still loads.
- Commit and push only the scoped documentation files.

For future implementation slices:

- Add unit tests for every new model, policy, store, connector, scheduler, and
  trust-state transition.
- Add controlled local HTML or UI tests for page action behavior.
- Add benchmark-output fixtures before claiming public Strawberry parity.
- Do not claim parity if validation is red; document exact failing commands and
  blockers instead.
