# Swift Strawberry Equivalence Plan

This is the Swift-app version of `STRAWBERRY.md`. It targets the native app under `swift/dBrowser` instead of the Rust/Tauri runtime.

## Goal

Close the Strawberry-equivalence gaps in the Swift app:

- Copilot can read the real active page.
- Copilot can click, type, scroll, navigate, and wait in the real `WKWebView`.
- Important actions remain approval-gated.
- Users see live run activity and can stop/take over.
- AI credit usage is metered only when model work happens.
- Workflows can be saved, rerun, scheduled where iOS allows, and run concurrently.
- Smart History recalls locally stored page summaries.
- Chain-backed browsing and wallet state are verified through embedded light clients or clearly labeled fallback modes.

## Current Swift App Evidence

The Swift app already has the right shell, but not the automation primitives:

- `swift/dBrowser/dBrowser/BrowserWebView.swift` wraps the active tab in `WKWebView`, tracks navigation, and accepts only toolbar commands.
- `swift/dBrowser/dBrowser/BrowserModels.swift` defines tabs, history, bookmarks, panels, and typed web commands.
- `swift/dBrowser/dBrowser/BrowserViewModel.swift` owns tabs, navigation, history, bookmarks, and runtime bridge status.
- `swift/dBrowser/dBrowser/RuntimeBridge.swift` exposes Copilot, wallet, downloads, decentralized resolution, and AFM service integration.
- `swift/dBrowser/dBrowser/ContentView.swift` renders the Copilot panel as one prompt/result flow.
- `swift/dBrowser/dBrowserTests/dBrowserTests.swift` already covers URL resolution, runtime features, AFM services, history, bookmarks, and autocomplete.

The missing pieces are a typed `WKWebView` request/response bridge, real DOM extraction/actions, streaming run state, persistent workflow/history storage, and chain verification beyond gateway/RPC fallback.

## GitHub Issue Map

Core Strawberry steps:

- #50 - Add a `WKWebView` automation bridge.
- #51 - Implement DOM query extraction for the active `WKWebView` tab.
- #52 - Make Copilot DOM actions control the real page.
- #53 - Add page snapshots for Copilot context.
- #54 - Stream Copilot activity and support cancellation/takeover.
- #55 - Meter Copilot credits only for AI work.
- #56 - Add saved and scheduled mobile Copilot workflows.
- #57 - Add a concurrent Copilot runs surface.
- #58 - Add local Smart History recall.

Chain trust and light-client issues:

- #68 - Add a shared light-client registry and trust-state UI.
- #59 - Integrate a Bitcoin SPV or compact-filter light client.
- #60 - Integrate Ethereum and EVM-family light clients.
- #61 - Integrate Solana light-client verification.
- #62 - Integrate Cosmos SDK and Tendermint light clients.
- #63 - Integrate Polkadot and Substrate light clients.
- #64 - Integrate Avalanche light-client verification.
- #65 - Integrate TRON light-client or proof-verified fallback.
- #66 - Integrate XRP Ledger verification.
- #67 - Integrate Move-chain light clients for Sui and Aptos.

## P0 Step Sequence

### Step 1 - Build a `WKWebView` Automation Bridge (#50)

Add a tab-scoped, request/response bridge in Swift:

- Define typed commands/results in `BrowserModels.swift` or a new file such as `BrowserAutomation.swift`.
- Extend `BrowserWebView` with a controlled `WKUserContentController` and audited app-owned scripts.
- Correlate replies by request ID and `BrowserTab.id`.
- Add timeouts and typed errors for missing tabs, navigation changes, JavaScript errors, and late replies.
- JSON-encode selectors/text into audited scripts. Do not expose arbitrary model-provided JavaScript.

Definition of done:

- Swift code can request an automation command for a specific tab and receive a typed result.
- Late replies are ignored.
- Tests cover encoding, tab scoping, timeout, and error behavior.

### Step 2 - Implement DOM Query Extraction (#51)

Use the bridge to add a bounded DOM query primitive:

- Query by selector and limit.
- Return tag, role, ARIA label, visible text, value, href/src/action, disabled/hidden state, and stable index.
- Enforce element and payload caps before data reaches Copilot.
- Route through `BrowserViewModel` and `MobileRuntimeBridge` without raw JavaScript exposure.

Definition of done:

- Copilot/runtime code can request safe DOM query results for the active tab.
- Oversized output is truncated with metadata.
- Tests cover validation and truncation.

### Step 3 - Make Page Actions Real (#52)

Add typed page actions:

- Click element.
- Type text.
- Focus field.
- Submit form.
- Scroll.
- Navigate.
- Wait for selector.
- Stop pending automation.

Approval gates:

- Form submit.
- Downloads.
- Wallet/signing/spend.
- Cross-origin navigation.
- Destructive or purchase-like clicks.
- Credential/password fields.

Definition of done:

- Actions visibly affect controlled `WKWebView` test content.
- Sensitive actions return `needsApproval`.
- Action results include success/failure, affected element summary, and current URL/title.

### Step 4 - Add Page Snapshot (#53)

Add the default "what is in front of me" tool:

- URL and title.
- Main visible text.
- Headings.
- Key links.
- Key buttons.
- Forms and controls.
- Metadata and current selection/focus where useful.

Privacy requirements:

- Redact credential fields.
- Exclude hidden fields unless explicitly requested by a user-approved diagnostic flow.
- Cap text and element count for mobile memory and model context.

Definition of done:

- `runCopilot` can attach a bounded page snapshot.
- Snapshot failure degrades to URL-only mode with visible status.
- Tests cover redaction and truncation.

### Step 5 - Stream Activity and Cancellation (#54)

Replace single-result Copilot execution with run state:

- Add `CopilotRun` with run ID, tab ID, status, timestamps, events, approvals, and usage.
- Emit events for snapshots, model calls, tool calls, approvals, page actions, and errors.
- Add Stop/take-over controls in `CopilotPanelView`.
- Cancel automation when users manually navigate, close the target tab, or issue toolbar commands that invalidate the run.

Definition of done:

- Users can see live Copilot activity.
- Canceled runs cannot keep acting on the page.
- Tests cover run transitions and cancellation.

### Step 6 - Meter Credits Only for AI Work (#55)

Add Swift-side credit accounting:

- Browser-only operations cost zero credits.
- DOM query, page snapshot, and page automation cost zero credits unless a model is called.
- Model calls report prompt tokens, output tokens, exact/estimated flag, provider, and credits spent.
- AFM service usage is passed through when provided.
- Local/provider responses without token usage use a deterministic estimator.

Definition of done:

- Every Copilot run reports exact or estimated usage.
- Users can inspect credits per run.
- Tests cover zero-cost browser operations, estimated usage, and AFM usage passthrough.

## P1/P2 Product Parity

### Step 7 - Saved and Scheduled Workflows (#56)

Add reusable mobile workflows:

- Title.
- Prompt template.
- Target URL or URL pattern.
- Allowed actions.
- Schedule metadata.
- Last run status.
- Enabled/disabled state.

Persist workflows locally and make iOS background limitations explicit. Scheduled work must use the same snapshot, approval, activity, and credit-metering paths as manual runs.

### Step 8 - Concurrent Runs Surface (#57)

Add a central run registry:

- Active, queued, completed, failed, and canceled runs.
- Per-tab scoping.
- Recent-run history.
- Concurrency limits for mobile model calls and page automation.
- Compact surface in Copilot and status bar.

### Step 9 - Local Smart History (#58)

Extend history beyond URL/title:

- Persist history locally.
- Store bounded page summaries from snapshots.
- Add natural-language recall over local summaries.
- Integrate recall into address autocomplete and Copilot context selection.
- Add controls to clear summaries and exclude pages/domains.

Smart History must stay local by default. Remote services only receive selected, user-approved context.

## Chain Trust Track

The Swift runtime should not treat gateway/RPC responses as the trust root for chain-backed state. Add a shared registry first (#68), then chain-specific adapters.

### Shared Registry (#68)

Add one Swift-facing source of truth for chain status:

- `unavailable`
- `syncing`
- `verified`
- `proofChecked`
- `rpcFallback`
- `stale`
- `failed`

Every chain client should expose:

- chain ID/name
- sync height or checkpoint
- trust source
- supported proof types
- last verification error
- fallback reason

Runtime UI should show the difference between verified light-client mode and fallback transport.

### Bitcoin (#59)

Bitcoin should use SPV or compact-filter verification on mobile, not a full node inside the iOS app.

Notes:

- Bitcoin has light-client designs. SPV verifies transaction inclusion with block headers and Merkle proofs.
- BIP157/158 compact filters power Neutrino-style clients and are designed for mobile Lightning-style clients.
- Bitcoin Core can serve compact-filter data, but Bitcoin Core itself is a full-node client, not the embeddable Swift light client.
- A pruned Bitcoin Core node is still a fully validating node after it downloads and validates the chain, but it discards old block data and is better suited as an optional desktop/server companion than an iOS embedded runtime.

Current full-node sizing:

- YCharts/Blockchain.com reports Bitcoin blockchain size at 740.64 GB for May 15, 2026, excluding database indexes.
- Bitcoin.org also describes the initial block download as roughly 740 GB.
- A non-pruned full node should be budgeted closer to 800 GB to 1 TB after indexes, chainstate, wallet data, and operational headroom.
- Pruned nodes can reduce retained disk use substantially, but they still need to download and validate the full chain during sync.

References:

- https://bitcoin.org/en/full-node
- https://ycharts.com/indicators/bitcoin_blockchain_size?cat=228
- https://github.com/lightninglabs/neutrino
- https://bitcoindevkit.org/blog/compact-filters-demo/

### Ethereum and EVM Family (#60)

Support Ethereum mainnet first, then map EVM-family chains and L2s by trust model:

- Ethereum mainnet.
- Base.
- Arbitrum.
- Optimism.
- Polygon.
- BNB Chain.
- Avalanche C-Chain.

Do not treat every EVM endpoint as equivalent. L2 sequencer data, settlement proofs, finality, and fraud/validity proof status need separate labels.

### Solana (#61)

Solana needs a chain-specific trust strategy:

- slot/root tracking
- transaction confirmation
- account proof verification where supported
- stale RPC detection
- explicit labels for current proof gaps

RPC-only Solana data must never be shown as locally verified state.

### Cosmos SDK and Tendermint (#62)

Use Tendermint/CometBFT light-client verification where possible:

- headers
- validator set changes
- commit signatures
- trust periods
- IBC-related proof distinctions

### Polkadot and Substrate (#63)

Evaluate a Substrate light client such as `smoldot` through Swift-compatible FFI:

- relay chain headers
- parachain headers
- storage proofs
- runtime metadata
- chain specs
- finalized block tracking

### Avalanche (#64)

Avalanche needs explicit handling beyond generic EVM JSON-RPC:

- Primary Network consensus assumptions.
- C-Chain verification.
- subnet/L1 limitations.
- finality/accepted block status.

### TRON (#65)

TRON carries major stablecoin/payment activity, but proof support may not map cleanly to a local light client:

- evaluate available proof/light-client paths
- otherwise implement proof-checked or multi-source fallback
- label centralized API data as fallback

### XRP Ledger (#66)

XRPL has its own validator/trust-anchor model:

- validated ledger tracking
- ledger hash/index
- account state
- payment status
- trust lines
- configured validator assumptions

### Sui and Aptos (#67)

Move-chain support should be first-class:

- Sui checkpoint/object proof verification.
- Aptos state proof/light-client support.
- epoch/validator-set handling.
- object/account state.
- transaction effects.

## Verification Baseline

For documentation-only changes:

- Run a no-op Swift validation command that proves the project can still be loaded/tested.

For implementation changes:

- Add unit tests for every new model, policy, storage path, and trust-state transition.
- Add controlled local HTML tests for DOM read/action behavior where practical.
- Run the Swift/Xcode test lane for `swift/dBrowser`.
- Do not claim parity until local validation is green or blockers are documented with exact failing commands.
