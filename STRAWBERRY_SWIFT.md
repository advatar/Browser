# Swift Strawberry Parity Survey

Renewed: 2026-06-05
Tracker: https://github.com/advatar/Browser/issues/134

This survey keeps the Swift app at or above Strawberry Browser in browser-agent
features and user experience. It replaces the older "missing primitives" plan:
the Swift app now has many of the original Strawberry-equivalence foundations,
so the remaining work is mostly product polish, benchmark proof, integration
hardening, and recurring automation UX.

## Goal

Stay competitive with Strawberry on the capabilities users can feel:

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

dBrowser should also keep its differentiators visible: local MLX/SwiftLM model
paths, context-preserving model switching, governed OpenMind memory, AFMarket
runner packs, A2UI apps, decentralized protocol handling, wallet capabilities,
and chain-trust verification.

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
  chain-trust behavior.

## Parity Matrix

| Area | Strawberry 2026 public baseline | dBrowser Swift state | Remaining gap |
| --- | --- | --- | --- |
| Distribution | Open beta for macOS and Windows. | Native Swift app targets Apple platforms. | Windows parity is absent unless a separate shell is declared or built. |
| Browser switching | Imports passwords, bookmarks, and history from major browsers and can run alongside them. | Tabs, history, bookmarks, protocol handling, and native shell exist. | First-run import, default-browser setup, and switcher UX are not documented as complete. |
| Companion onboarding | Role/app/workflow onboarding creates a personalized companion. | OpenMind memory, local profile state, A2UI apps, and Copilot exist. | Need a first-run assistant setup that suggests workflows and learns preferences explicitly. |
| Page context | Current page, structure, conversation memory, and other tabs when relevant. | Active-page snapshot, bounded DOM extraction, transcript ledger, memory citations. | Need relevance-scored multi-tab context and video/transcript handling. |
| Research | Parallel research, multi-source synthesis, dated/source-linked outputs. | Copilot runs, model routing, AFMarket, page snapshots, local Smart History. | Need a research planner, parallel tab/run orchestration, source ledger, and export schema. |
| Page actions | Click, fill, scroll, navigate, select, submit, download, and end-to-end workflows. | Typed click, type, focus, submit, scroll, navigate, wait, stop with approval policy. | Need richer recovery, download handling, select/menu actions, and controlled UI/end-to-end automation tests. |
| Workflows | Save, rerun, schedule, trigger, monitor changes, and notify. | Saved workflow persistence, run/rerun, schedule metadata, run registry. | Need real scheduler, page-change triggers, notifications, recurrence limits, and pause/resume controls. |
| Integrations | Built-in app integrations plus MCP. | MCP profiles, A2UI app store, AFMarket, OpenMind, wallet capability contracts. | Need production OAuth connectors, credential storage, revocation, and built-in app catalog UX. |
| Safety | Approval before important actions, stop/takeover, activity history. | Approval reasons, run events, Stop, cancellation on invalidating navigation/tab close. | Need longer-lived audit history, approval policy presets such as "allow all", and user-visible risk explanations. |
| Privacy | Local chats/passwords/history/cookies, Smart History disabled by default. | Local stores and governed memory exist; Smart History summaries are local. | Need explicit Smart History opt-in/default controls and per-provider data-egress labels for every run. |
| Credits | Browsing is free; credits only for companion chat/browsing. | Browser operation zero-cost model and estimated model usage exist. | Need exact provider token passthrough where available, plan/balance UI, and run-level billing receipts. |
| Benchmarks | Publishes 12-workflow spec and claimed scores. | No comparable benchmark runner or public score artifact in the Swift tree. | Need a reproducible dBrowser benchmark lane and published result artifacts. |

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

## Prioritized Gap-Closure Plan

### P0 - Prove and Package Parity

1. Build a Strawberry benchmark runner for dBrowser.
   - Mirror Strawberry B1-B12 inputs, output schema, timing metadata, blockers,
     and LLM-as-judge prompt.
   - Allow 9-benchmark mode without Sales Navigator/CRM/ATS access and 12-benchmark
     mode when test credentials are configured.
   - Persist markdown/CSV outputs plus score artifacts under a repo-owned
     validation path.
   - Add tests for benchmark spec parsing, output validation, and scoring-input
     generation.

2. Add first-run companion onboarding.
   - Ask for role, common tools, preferred outputs, risk tolerance, and recurring
     browser work.
   - Suggest A2UI apps, MCP profiles, AFMarket packs, OpenMind memory posture,
     and starter workflows.
   - Store the resulting profile locally and make every learned preference
     editable or removable.
   - Add unit tests for profile persistence, workflow suggestions, and reset.

3. Build browser import and switcher UX.
   - Import bookmarks and history from Chrome, Safari, Firefox, Edge, Arc, and
     Brave where platform APIs allow it.
   - Treat password and cookie import as explicit, high-risk flows backed by
     platform keychain APIs and clear non-support states where import is blocked.
   - Add a "use alongside existing browser" onboarding path and default-browser
     setup guidance.
   - Add tests for import parsing, dedupe, error states, and no-secret logging.

4. Turn workflow metadata into real recurring automation.
   - Add scheduler execution, page-change monitoring, content-appears/disappears
     triggers, notification delivery, recurrence limits, and cooldowns.
   - Keep submit/download/wallet/signing/destructive actions approval-gated even
     for recurring workflows unless an explicit scoped policy allows them.
   - Add pause/resume, last-run detail, next-run preview, and failure backoff.
   - Add unit tests for triggers, schedules, cooldowns, approvals, and cancellation.

### P1 - Close UX Depth Gaps

5. Add a research planner and source ledger.
   - Let Copilot split research into parallel tab/run groups.
   - Record source URL, title, retrieval date, confidence, and extracted evidence.
   - Export markdown, CSV, and A2UI table outputs.
   - Add tests for source dedupe, source dating, confidence labels, and export
     schema validation.

6. Harden integrations and MCP for production use.
   - Add built-in connector profiles for Google Workspace/Gmail, Microsoft 365,
     Slack, Notion, CRM/ATS, calendar, notes, and email.
   - Store secrets in Keychain or the existing encrypted MCP profile service.
   - Expose scopes, tool allowlists, revocation, connection test results, and
     last-used audit state.
   - Add tests for redacted persistence, revocation, disabled tools, and failed
     connector states.

7. Expand page action coverage and resilience.
   - Add select/menu, download, file-pick/upload metadata, new-tab handling,
     retry/recovery, and better affected-element summaries.
   - Add controlled `WKWebView` HTML fixtures or UI tests for visible action
     effects on forms, menus, pagination, downloads, and navigation.
   - Keep arbitrary model-provided JavaScript out of the bridge.

8. Make privacy and credit posture explicit.
   - Ship Smart History as an explicit opt-in with local-only, provider-assisted,
     and disabled modes clearly labeled.
   - Show a per-run data-egress receipt: model/provider, page snapshot, memory
     citations, connector tools, and omitted context commitments.
   - Use exact token/credit values when providers return them; otherwise show
     deterministic estimates with reason labels.
   - Add tests for opt-in defaults, egress receipts, provider usage passthrough,
     and estimator fallbacks.

### P2 - Exceed Strawberry Where dBrowser Is Unique

9. Promote A2UI apps into companion templates.
   - Package sales, recruiting, operations, marketing, data extraction, research,
     travel, shopping, forms, and monitoring flows as installable companion apps.
   - Let each template declare required capabilities, connectors, page actions,
     approval policy, runtime profile, and benchmark coverage.

10. Make local-first model switching a headline UX.
    - Present local MLX, SwiftLM, LLM Router, AFMarket, and LLM Gateway choices
      as a trust/cost/performance control, not only a picker.
    - Keep model-switch context continuity and compression events visible.
    - Add "keep this local" and "fastest available" run modes.

11. Keep decentralized and chain trust advantages visible.
    - Tie A2UI apps, wallet actions, protocol loading, AFMarket settlement, and
      chain-trust status into one approval and evidence surface.
    - Make verified, proof-checked, RPC fallback, and unavailable states obvious
      wherever browser-agent work touches crypto or decentralized content.

12. Decide Windows parity explicitly.
    - If "at or above Strawberry" requires Windows, create a separate shell plan
      for Windows rather than pretending Swift covers it.
    - If Windows is not a product goal, document the trade: macOS/iOS native
      integration plus local MLX, wallet, A2UI, and decentralized capabilities.

## Verification Baseline

For this documentation-only renewal:

- Run Markdown hygiene checks on `STATUS.md` and `STRAWBERRY_SWIFT.md`.
- Run a local Swift/Xcode build to prove the project still loads.
- Commit and push only the scoped documentation files.

For future implementation slices:

- Add unit tests for every new model, policy, store, connector, scheduler, and
  trust-state transition.
- Add controlled local HTML or UI tests for page action behavior.
- Add benchmark-output fixtures before claiming public Strawberry parity.
- Do not claim parity if validation is red; document exact failing commands and
  blockers instead.
