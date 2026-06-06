# dBrowser Current Architecture And Plan

This is the single source of truth for the current dBrowser architecture and implementation plan.

The product has transitioned to Swift completely. The current app is the native Swift app under `swift/dBrowser`. Any capability that exists only in the old Rust/Tauri runtime is historical implementation evidence, not current product functionality. Rust-only functionality must be recreated as Swift packages and integrated with the Swift app before it counts as supported.

## Current Product Boundary

Current product:

- Native Swift app: `swift/dBrowser`.
- SwiftUI shell: `ContentView.swift`.
- Browser state and navigation: `BrowserViewModel.swift` and `BrowserModels.swift`.
- Web rendering: `BrowserWebView.swift` wrapping `WKWebView`.
- Runtime integration boundary: `RuntimeBridge.swift`.
- AFMarket service client: `AFMServicesClient.swift`.
- Local MLX model selection: `BundledLLM.swift`.
- Unit tests: `swift/dBrowser/dBrowserTests/dBrowserTests.swift`.

Legacy/reference only:

- Rust crates under `crates/`.
- Tauri GUI and runtime frontend.
- Old Rust agent runtime, wallet, IPFS, p2p, updater, AFM, and light-client code.
- Old Node service docs unless they describe external contracts the Swift app still calls.

The migration rule is simple: if Swift cannot call it through a Swift package or a documented service contract, it is not current architecture.

## Product Goal

dBrowser is a native Swift browser and agent surface for decentralized browsing, local-first AI, governed personal memory, AFMarket task execution, and chain-verified wallet/protocol state.

The strategic north star is to make dBrowser the Web3 and AI browser to beat: a native browser where AI agents can research, negotiate, prepare forms, compare carts, call tools, and coordinate payment flows, but cannot move money or disclose identity without typed policy, verified identity context, explicit user approval, and a durable local receipt.

The app should:

- Load normal web pages in `WKWebView`.
- Resolve IPFS, IPNS, ENS, and other decentralized addresses through verified light-client paths where possible, with clearly labeled gateway fallback.
- Provide a desktop-class LLM conversation UI similar in scope to Claude Desktop or ChatGPT Desktop.
- Let the user switch the active LLM at any point while preserving conversation context.
- Let the LLM surface read and operate the real active page through typed, approval-gated automation.
- Use local MLX models by default when they are suitable.
- Route larger or specialized work through AFMarket runner packs.
- Retrieve and write personal memory only through BrIAn/OpenMind MCP policy gates.
- Keep wallet signing, spend policy, memory writeback, downloads, and destructive page actions behind explicit user approval.
- Surface proof, attestation, settlement, and light-client trust state in the UI.
- Support EUDI Wallet-compatible identity and attestation flows as a user-controlled credential boundary.
- Support agentic payment protocols only through typed intents, signed/hashed authorization artifacts, revocation, and approval receipts.

## EUDI Wallet And Agentic Payments Plan

Tracker: https://github.com/advatar/Browser/issues/138

Primary sources inspected on 2026-06-06:

- European Commission European Digital Identity overview: https://commission.europa.eu/topics/digital-economy-and-society/european-digital-identity_en
- EUDI Wallet Architecture and Reference Framework: https://eudi.dev/latest/architecture-and-reference-framework-main/
- EUDI Wallet ARF repository: https://github.com/eu-digital-identity-wallet/eudi-doc-architecture-and-reference-framework
- EUDI iOS Wallet Kit: https://github.com/eu-digital-identity-wallet/eudi-lib-ios-wallet-kit
- Google AP2 announcement and repository: https://cloud.google.com/blog/products/ai-machine-learning/announcing-agents-to-payments-ap2-protocol and https://github.com/google-agentic-commerce/AP2
- Visa Trusted Agent Protocol overview and specification: https://developer.visa.com/capabilities/trusted-agent-protocol/overview and https://developer.visa.com/capabilities/trusted-agent-protocol/trusted-agent-protocol-specifications/
- Notabene Transaction Authorization Protocol: https://notabene.id/tap
- Stripe/OpenAI Agentic Commerce Protocol: https://docs.stripe.com/agentic-commerce/acp and https://github.com/agentic-commerce-protocol/agentic-commerce-protocol
- x402 payment standard and docs: https://www.x402.org/ and https://docs.x402.org/introduction
- Mastercard Agent Pay and agentic commerce standards notes: https://www.mastercard.com/us/en/news-and-trends/press/2025/april/mastercard-unveils-agent-pay-pioneering-agentic-payments-technology-to-power-commerce-in-the-age-of-ai.html and https://www.mastercard.com/us/en/news-and-trends/stories/2026/agentic-commerce-rules-of-the-road.html

Terminology:

- "A2P" appears in market commentary, but the canonical Google artifact is AP2, the Agent Payments Protocol.
- "TAP" is overloaded. Visa Trusted Agent Protocol handles agent recognition and merchant verification. Notabene Transaction Authorization Protocol handles blockchain pre-settlement authorization between counterparties.
- EUDI Wallet is an identity and attestation wallet framework, not a payment wallet by itself. It matters because agentic payments need strong identity, user authentication, selective disclosure, signatures, and revocable delegation.

Protocol map:

| Layer | Source | What It Gives dBrowser | First Adapter |
| --- | --- | --- | --- |
| EU identity and attestations | EUDI Wallet ARF and iOS Wallet Kit | PID, attestations, OpenID4VCI issuance, OpenID4VP presentation, ISO 18013-5 proximity flows, SD-JWT VC, pseudonyms, and strong user authentication use cases | `EUDIIdentityKit` |
| Agent payment authorization | Google AP2 | Intent/cart/payment mandate models, signed authorization artifacts, hashes, expiry, budget, credential source, and audit trail | `AgentPaymentMandateKit` |
| Agent recognition | Visa Trusted Agent Protocol | Request signatures, key discovery, agent recognition, consumer/device identity object, and payment container verification for merchant interactions | `TrustedAgentKit` |
| Agent checkout | ACP | Agent-presented checkout, merchant order handoff, shared payment token and delegated payment flows | `AgenticCommerceKit` |
| Machine-to-machine Web3 payments | x402 | HTTP 402 payment negotiation, buyer/server/facilitator model, API/content micropayment receipts, crypto-native settlement | `X402PaymentsKit` |
| Blockchain pre-settlement authorization | Notabene TAP | Signed transfer requests, encrypted counterparty messages, authorization before blockchain settlement | `BlockchainAuthorizationKit` |
| Card-network agent payments | Mastercard Agent Pay, Visa Intelligent Commerce | Network tokenization, verifiable intent, payment passkeys, issuer/processor policy integration | `NetworkAgentPayKit` |
| Tool and agent coordination | MCP, A2A, A2UI, AFMarket | Tool discovery, agent-to-agent calls, native app surfaces, proof-backed runner packs, settlement evidence | Existing MCP/A2UI/AFMarket surfaces |

The policy architecture:

```mermaid
graph TD
  User["User"] --> Approval["dBrowser Approval And Receipt UI"]
  Page["WKWebView Page Context"] --> Copilot["Copilot / A2UI / MCP Agent"]
  Copilot --> Policy["Agent Payment Policy Engine"]
  Approval --> Policy
  Policy --> Identity["EUDIIdentityKit"]
  Policy --> Wallet["WalletPolicyKit / ChainTrustKit"]
  Policy --> Mandates["AgentPaymentMandateKit AP2"]
  Mandates --> Commerce["ACP / NetworkAgentPayKit"]
  Mandates --> X402["X402PaymentsKit"]
  Mandates --> TAP["TrustedAgentKit / BlockchainAuthorizationKit"]
  Wallet --> Chains["Light Clients / WalletConnect / Secure Enclave"]
  Identity --> EUDI["EUDI Wallet Kit / Relying Party Flows"]
  Commerce --> Merchant["Merchant / PSP / Card Network"]
  X402 --> Service["Paid API / Content Server / Facilitator"]
  TAP --> Counterparty["Merchant / Exchange / Smart Contract Counterparty"]
  Policy --> Receipt["Local Receipt Ledger"]
```

Safety invariants:

- No model can directly spend, sign, submit, broadcast, tokenize, or disclose identity.
- Every payment-capable action must have a typed intent, merchant or counterparty, amount or maximum amount, currency or asset, expiry, recurrence state, credential source, and revocation path.
- Every approval must bind to page snapshot hash, cart or transfer hash, mandate hash, wallet/account, chain/network, identity credential, model, tool, connector, and user action.
- Recurring or autonomous payments require explicit opt-in, spend caps, cooldowns, failure backoff, next-run preview, and one-click revocation.
- Payment approvals must be invalidated by cart mutation, recipient mutation, price increase beyond policy, chain/network change, credential change, or prompt-injection risk.
- Secrets stay in Keychain, Secure Enclave, WalletConnect, certified wallet flows, or approved provider vaults. dBrowser should not store card PANs.
- Mock, fixture, sandbox, local, gateway, provider, verified, revoked, and failed states must be distinct in models and UI.

Initial Swift models:

- `AgentPaymentIntent`: objective normalized into amount, merchant/counterparty, allowed categories, currency/asset, expiry, recurrence, and risk posture.
- `AgentPaymentCart`: item, price, tax, shipping, merchant, refund, delivery, checkout, and source-page hash.
- `AgentPaymentMandate`: AP2-style intent/cart/payment mandate envelope with signer, hash, expiry, scope, credential reference, and revocation state.
- `AgentPaymentProtocol`: `ap2`, `acp`, `x402`, `visaTrustedAgent`, `notabeneTap`, `mastercardAgentPay`, `manualApproval`.
- `EUDICredentialPresentation`: relying party, requested attributes, purpose, legal basis text, selective-disclosure result, pseudonym mode, and wallet approval state.
- `AgentTrustAttestation`: agent identifier, request signature, key source, payment scheme, verification result, and failure reason.
- `PaymentPolicyDecision`: allow, ask, deny, step-up, revise, revoke, or expired.
- `PaymentReceipt`: local immutable receipt binding identity, wallet, page, model, connector, mandate, cart, transaction, and user approval metadata.
- `RecurringPaymentPolicy`: cap, cadence, merchant allowlist, revocation, cooldown, last-run, next-run, failure, and notification state.

Product surface:

- Wallet panel becomes "Wallet, Identity & Payments" or gains an adjacent Identity/Payments tab.
- Copilot and A2UI apps can propose payment intents, but they open a review sheet instead of submitting checkout directly.
- Review sheet shows merchant/counterparty, amount, asset/currency, recurrence, identity attributes requested, model/tool provenance, page/cart hash, network trust, and exact approval consequence.
- Receipt ledger shows approved, denied, expired, revoked, failed, refunded, and settled states.
- MCP/A2UI apps declare payment capability requirements in the same style as wallet and chain grants.

Implementation phases:

1. Add Swift-only protocol models and fixtures for EUDI credential requests, AP2 mandates, ACP checkout drafts, x402 payment requirements, Visa TAP signatures, Notabene TAP transfer requests, and network-agent-pay abstractions.
2. Add tests for normalization, redaction, hash binding, policy decisions, recurring limits, expiry, revocation, and receipt generation.
3. Add a payment intent review surface in the Wallet panel and Copilot flow.
4. Spike `EUDIIdentityKit` with EUDI iOS Wallet Kit where licensing and platform targets fit; keep certification status explicit.
5. Implement local AP2, ACP, x402, Visa TAP, Notabene TAP, and Mastercard Agent Pay fixtures before any provider or sandbox integration.
6. Add sandbox-only clients where developer access is available; avoid real payment method collection unless handled by a certified or PCI-ready provider flow.
7. Add an agentic payments benchmark lane covering EUDI presentation, AP2 human-present cart approval, AP2 capped budget approval/denial, x402 paid API access, and Notabene TAP-style transfer authorization.

Compliance notes:

- Until certification and national wallet-provider requirements are understood, dBrowser should present EUDI support as relying-party/client integration and test harness work, not certified wallet-provider status.
- Card-network and PSP integrations must avoid storing PANs and must use provider-hosted, tokenized, or certified flows.
- Blockchain payment flows need sanctions, Travel Rule, counterparty, and fraud policy hooks where applicable.
- Prompt injection is a financial risk. Payment policy must trust typed artifacts, hashes, signatures, and user approvals over model claims.
- Provider terms can limit signing, key publication, and merchant simulation. Each adapter needs a terms/availability state before production use.

Open decisions:

- Whether dBrowser should become an EUDI wallet provider, a wallet-compatible relying-party client, or both.
- Whether a Windows shell is required for public "at or above Strawberry" claims.
- Which payment sandboxes are available first: AP2, ACP, x402, Visa, Mastercard, Notabene, or provider-specific rails.
- Whether recurring autonomous payments should launch with deny-by-default policy only, or with scoped allowlists for low-risk paid APIs.
- How much of the payment receipt ledger should be exportable for enterprise compliance without leaking private page, identity, or wallet data.

## Current Swift App

The current Swift app already has a usable shell:

| Surface | Current implementation | Status |
| --- | --- | --- |
| Browser chrome | `ContentView.swift` renders toolbar, address bar, tab strip, status bar, home, panels | Current |
| Web rendering | `BrowserWebView.swift` owns a `WKWebView`, navigation delegate, back/forward/reload/stop commands | Current |
| Tabs/history/bookmarks | `BrowserViewModel.swift` manages in-memory tabs, history, bookmarks, autocomplete | Current |
| URL resolution | `BrowserURLResolver` accepts HTTP/HTTPS, blocks unsupported schemes, delegates IPFS/IPNS/ENS to runtime bridge | Current |
| Runtime status | `MobileRuntimeBridge` exposes feature states for browsing, decentralized protocols, AFM, Copilot, wallet, downloads | Current |
| AFM service checks | `AFMServicesClient` checks router, registry, pipelines, node, and local marketplace services; it calls route, pack, job, training, publish, and marketplace discovery APIs | Prototype |
| Copilot | `runCopilot` routes through AFM services when available, otherwise returns deterministic local fallback | Prototype |
| Wallet | Local typed policy simulator for connect/disconnect/spend decision | Prototype |
| Downloads | Native `URLSession` download tracking with queued/downloading/completed/cancelled/failed states | Current |
| Bundled LLM | Gemma 4 E2B IT 4-bit MLX through `mlx-swift-lm` packages | Current selection, inference integration next |
| Decentralized storage handlers | `services/storage-adapters` binds the Swift localhost adapter ports and validates/proxies protocol-specific native handler requests | Local service contract |

Current limitations:

- Typed `WKWebView` automation, DOM snapshots, page actions, Copilot run state,
  model switching, saved workflows, Smart History, wallet/explorer state, and
  the Strawberry parity scorecard are implemented in Swift, but still need
  deeper production UX, fixture-backed UI coverage, and public benchmark
  artifacts.
- Browser import/switcher, companion onboarding, research source ledger,
  recurring workflow automation, and benchmark proof currently exist as tested
  Swift models; first-run UI, scheduler execution, and exported benchmark lanes
  remain product work.
- Decentralized storage protocols use direct gateways where safe, then localhost
  native adapter handlers. Arbitrary bytes for heavy protocols still require the
  corresponding local daemon or backend to be configured behind
  `services/storage-adapters` until native protocol engine bundling is complete.
- Wallet and chain trust have typed policy/explorer surfaces and chain-family
  models; production signing, Secure Enclave policies, WalletConnect, and full
  Swift light-client integration remain staged work.
- EUDI Wallet, AP2, ACP, x402, Visa TAP, Notabene TAP, and Mastercard Agent Pay
  support is planned under #138 and is not yet implemented beyond this
  architecture plan.

## Swift System Map

```mermaid
graph TD
  User["User"] --> SwiftUI["SwiftUI Shell"]
  SwiftUI --> ViewModel["BrowserViewModel"]
  ViewModel --> WebView["WKWebView"]
  ViewModel --> Runtime["MobileRuntimeBridge"]

  Runtime --> AFM["AFMarketKit"]
  Runtime --> Memory["OpenMindMemoryKit"]
  Runtime --> Chain["ChainTrustKit"]
  Runtime --> Wallet["WalletPolicyKit"]
  Runtime --> Conversation["LLMConversationKit"]
  Conversation --> LLM["BundledLLMKit / LLMGatewayKit"]
  Runtime --> Automation["BrowserAutomationKit"]
  Runtime --> Content["DecentralizedContentKit"]

  AFM --> AFMarket["../AFMarket router / registry / node / pipelines"]
  Memory --> BrIAn["../OpenMind/BrIAn MCP / OMPS"]
  Chain --> LightClients["Bitcoin / Ethereum / Solana / Cosmos / Substrate / other light clients"]
  LLM --> ZeroK["ZeroK / LLM Gateway"]
  Content --> IPFS["IPFS / IPNS"]
```

The Swift app owns UI, state, approvals, and user-visible trust labels. Swift packages provide reusable capability boundaries. External projects provide service contracts, but the app should not depend on hidden Rust-only implementation paths.

## Package Architecture

Create Swift packages under `swift/Packages` as capabilities move out of old Rust-only code.

| Package | Responsibility | Recreates or integrates |
| --- | --- | --- |
| `BrowserAutomationKit` | Typed `WKWebView` request/response bridge, DOM snapshots, page actions, timeouts, redaction | Old browser automation and DOM action concepts |
| `AgentRuntimeKit` | Copilot runs, tool calls, approvals, cancellation, ledger, credit accounting, saved workflows | Old agent-core and ai-agent runtime |
| `LLMConversationKit` | Persistent conversations, messages, model registry, provider-neutral context ledger, model-switch events, prompt rendering | Old LLM/Copilot UX concepts, rebuilt for Swift |
| `AFMarketKit` | AFMarket marketplace, router, registry, node install/dispatch, leases, attestation, proof, settlement models | `../AFMarket` contracts and old AFM Rust crates |
| `OpenMindMemoryKit` | MCP client configuration, OMPS resources/tools, governed recall, step-up, memory writeback | `../OpenMind/BrIAn` OpenMind MCP packages |
| `ChainTrustKit` | Shared chain trust registry, light-client status, fallback labels, proof result models | Old blockchain/light-client concepts |
| `BitcoinLightClientKit` | Bitcoin SPV or compact-filter verification | Old `btc-light` concepts, implemented natively for Swift |
| `EthereumLightClientKit` | Ethereum and EVM-family light clients, ENS proofs, wallet state proofs | Old `eth-light` concepts |
| `SolanaLightClientKit` | Solana proof verification and finalized state checks | New Swift package |
| `TendermintLightClientKit` | Cosmos SDK and Tendermint client verification | New Swift package |
| `SubstrateLightClientKit` | Polkadot/Substrate verification, likely through Swift-compatible smoldot integration | Old Substrate ideas |
| `WalletPolicyKit` | Local keys, Secure Enclave, WalletConnect, spend/signature policy, approvals | Old walletd and wallet store concepts |
| `EUDIIdentityKit` | EUDI Wallet credential presentation, OpenID4VCI/OpenID4VP, ISO 18013-5, SD-JWT VC, pseudonym labels, relying-party fixtures | EUDI Wallet reference implementation and ARF |
| `AgentPaymentMandateKit` | AP2-style intent/cart/payment mandates, payment policy decisions, hashes, expiry, revocation, and local receipts | Google AP2 and dBrowser approval policy |
| `TrustedAgentKit` | Visa Trusted Agent Protocol request-signature verification, key-source metadata, agent recognition state, and merchant-facing trust labels | Visa TAP and HTTP message signature concepts |
| `AgenticCommerceKit` | ACP checkout drafts, merchant order handoff, shared-payment-token placeholders, and checkout receipt models | Stripe/OpenAI ACP |
| `X402PaymentsKit` | HTTP 402 payment requirements, buyer/server/facilitator fixtures, wallet policy binding, and API/content micropayment receipts | x402 |
| `BlockchainAuthorizationKit` | Notabene TAP-style transfer requests, encrypted counterparty-message metadata, pre-settlement approval receipts | Notabene Transaction Authorization Protocol |
| `DecentralizedContentKit` | IPFS/IPNS resolution, content verification, gateway fallback labels, future embedded node | Old IPFS/p2p concepts |
| `BundledLLMKit` | Local MLX model discovery, loading, inference, token accounting | Current `BundledLLM.swift` extracted into package |
| `LLMGatewayKit` | ZeroK/LLM Gateway encrypted envelopes, token-class padding, usage tickets, provider boundary labels | ZeroK/LLM Gateway contracts |
| `UpdateDistributionKit` | Signed update manifests, content-addressed release fetch, integrity checks | Old updater concepts |
| `DiagnosticsKit` | Local logs, test diagnostics, user-exportable support bundles, telemetry policy | Old telemetry concepts |

Package rule:

- No package may silently use an RPC/gateway as the trust root if the UI says verified.
- Mock, local, gateway, remote, and proof-verified modes must be distinct model states.
- Every package needs unit tests and fixture coverage before UI wiring.

## Current External Integrations

### AFMarket

AFMarket lives in `../AFMarket` and is the source of truth for runner-pack discovery, expert routing, node dispatch, attested AFM execution, and ZK settlement.

Current Swift app surface:

- `AFMServiceEndpointConfiguration` defaults to local router, registry, and pipelines endpoints.
- `AFMServicesClient` checks `/health`, reads `/packs`, posts `/route`, and posts `/jobs`.
- `MobileRuntimeBridge.runCopilot` uses AFM services when available.

Target Swift package:

- `AFMarketKit`.

Required contracts:

- Local marketplace training and pack API from `apps/afm-marketplace`, plus compatibility with `../AFMarket/afm-marketplace-starter`.
- Runner pack schemas from `../AFMarket/afm-marketplace-starter/lib/schema.ts` and `../AFMarket/pipelines/src/types.ts`.
- Registry schemas from `../AFMarket/registry/src/schemas.ts`.
- Router schemas from `../AFMarket/router/src/schemas.ts`.
- Node install API from `../AFMarket/node/src/http.rs`.
- API contracts from `../AFMarket/docs/api-contracts.md`.
- EVM escrow and verifier contracts from `../AFMarket/contracts`.
- Swift attested run shape from `../AFMarket/ZKAI/ZKAI/AFMTaskRunner.swift`.

Implementation plan:

- Add AFMarket endpoint configuration for marketplace, registry, router, node agent, and settlement chain.
- Add Codable models for packs, registry bundles, experts, router tasks, routes, node installs, result envelopes, proofs, and settlement metadata.
- Maintain the Swift marketplace surface for browsing, publishing, and installing runner packs.
- Install selected packs through `POST /packs/install`.
- Route Copilot runs through AFMarket when a compatible pack is selected.
- Reflect lease, dispatch, attestation, proof, and settlement status in Copilot activity.
- Bind AFMarket proof and escrow status into credit metering and chain trust UI.

Issue: #69.

### BrIAn And OpenMind MCP

BrIAn lives in `../OpenMind/BrIAn` and is the personal memory store and OpenMind control plane. dBrowser must interact with it through MCP/OMPS contracts, never by reading BrIAn storage directly.

Target Swift package:

- `OpenMindMemoryKit`.

Required contracts:

- Swift MCP client and OMPS client from `../OpenMind/BrIAn/Packages/OpenMindMCPClient`.
- Swift MCP server and OMPS core from `../OpenMind/BrIAn/Packages/OpenMindMCPServer`.
- MCP resources such as `mind://profile`, `mind://state`, `mind://continuity`, `mind://memories`, `mind://capabilities`, posture, grants, authorizations, and recommendations.
- MCP tools such as `mind.search_memories`, `mind.retrieve_evidence_bundle`, `mind.add_memory`, `event.append`, `proposal.create`, `gateway.evaluate_access_intent`, and step-up grant tools.

Implementation plan:

- Add BrIAn/OpenMind MCP endpoint configuration for stdio and HTTP transports.
- Negotiate capabilities before any recall or writeback.
- Build access intents from prompt, page URL, page snapshot metadata, requested purpose, sensitivity ceiling, and output mode.
- Evaluate access before recall through `gateway.evaluate_access_intent`.
- Retrieve only policy-gated memory context and surface allowed, redacted, blocked, and unavailable states.
- Require explicit user approval for memory writeback.
- Attach run ID, tab ID, page snapshot commitment, idempotency key, source metadata, and base revision where available.
- Reflect BrIAn posture, continuity, grants, authorizations, and step-up state in Copilot activity.

Issue: #70.

### ZeroK And LLM Gateway

ZeroK is the privacy and proof-oriented LLM gateway path. The Swift app currently exposes `https://zerok.cloud` and `https://llmos.showntell.dev` as runtime gateway starting points.

Target Swift packages:

- `LLMGatewayKit`.
- `BundledLLMKit`.

Implementation plan:

- Use local MLX models first when suitable.
- Send only selected and redacted page context to a gateway.
- Use encrypted envelopes, token-class padding, usage tickets, replay protection, and user-visible provider boundary labels.
- Keep browser history, personal memory, and tab state local unless the user explicitly shares context.
- Label provider exposure honestly: upstream providers may correlate decrypted prompt content and timing unless confidential inference is added.

### Decentralized Storage Adapter Service

`services/storage-adapters` is the local runtime surface behind the Swift native adapter URLs. It binds `127.0.0.1:4881-4892`, exposes `/dweb/<network>/native`, and has explicit handlers for Filecoin, Walrus, Iroh, Hypercore/Hyperdrive, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle.

The handler service is not a hidden centralized resolver. It validates the Swift adapter metadata, keeps the original URI and locator metadata inside the local boundary, redacts secret capabilities in rendered responses, and proxies only configured local protocol backends. When a backend is missing, the handler returns a protocol-specific backend-required response rather than pretending bytes were resolved.

Development command:

```sh
pnpm --filter @browser/storage-adapters dev
```

Important backend environment variables:

- `DBROWSER_<PROTOCOL>_HANDLER_URL` for a protocol-specific local bridge that accepts the adapter query contract.
- Protocol backend variables such as `FILECOIN_RETRIEVAL_BASE_URL`, `WALRUS_SITES_BASE_URL`, `IROH_BLOBS_GATEWAY_URL`, `HYPERDRIVE_GATEWAY_URL`, `SIA_RENTERD_BASE_URL`, `STORJ_LINKSHARING_BASE_URL`, `TAHOE_LAFS_GATEWAY_URL`, `AUTONOMI_CLIENT_GATEWAY_URL`, `BITTORRENT_ENGINE_URL`, `CERAMIC_NODE_URL`, `ORBITDB_GATEWAY_URL`, and `RADICLE_HTTPD_URL`.
- Credential variables stay in the local service boundary, for example `SIA_RENTERD_AUTH_HEADER`, `SIA_RENTERD_API_TOKEN`, and protocol-specific handler credentials.

### Blockchain Light Clients

The Swift runtime should not treat RPC or HTTP gateways as trust roots for chain-backed state. The app needs a shared `ChainTrustKit` registry first, then chain-specific Swift light-client packages.

Shared trust states:

- `unavailable`
- `syncing`
- `verified`
- `proofChecked`
- `rpcFallback`
- `gatewayFallback`
- `stale`
- `failed`

Each chain adapter must expose:

- chain ID and network name
- sync height or checkpoint
- trust source
- supported proof types
- last verification error
- fallback reason

Required chain packages:

- Bitcoin SPV or compact-filter client (#59).
- Ethereum and EVM-family clients (#60).
- Solana verification (#61).
- Cosmos SDK and Tendermint clients (#62).
- Polkadot/Substrate client (#63).
- Avalanche verification (#64).
- TRON light-client or proof-verified fallback (#65).
- XRP Ledger verification (#66).
- Sui and Aptos Move-chain clients (#67).

Bitcoin note:

- Bitcoin Core is a full-node client, not the embeddable Swift light client.
- Bitcoin does not ship a single official embeddable Swift light client with Bitcoin Core.
- A mobile Swift app should use SPV or compact-filter verification.
- A pruned/full Bitcoin Core node can be an optional desktop/server companion, but it must not be represented as the iOS embedded runtime.
- As of May 2026, bitcoin.org lists unpruned Bitcoin Core storage as over 750 GB and pruned storage as around 7 GB, after still downloading and validating the chain.

### KeyMeIn

`KeyMeIn` is not an active dependency in the current Swift app.

Adopt it only if dBrowser needs production attestation-gated signing, identity-gated authorization, threshold signing, JWKS receipt verification, or an external signing policy system. The integration point should be `WalletPolicyKit` or gateway authorization, not browser rendering.

## LLM Conversation And Page Automation Plan

The key gap is a first-class Swift LLM surface that can hold real conversation context, switch models without losing that context, and operate the active `WKWebView` page through approved typed actions.

The target UI should feel like a native desktop chat app:

- Persistent conversation list.
- Main message timeline with streamed assistant output.
- Composer with model picker, page-context attachment, file/context attachments, and stop/regenerate controls.
- Visible run activity for tool calls, memory access, AFMarket dispatch, chain verification, and approvals.
- Per-message model identity and boundary labels: local MLX, ZeroK/LLM Gateway, AFMarket runner pack, or other provider.
- Clear empty, loading, offline, provider-failed, and context-compressed states.

Context continuity rule:

- Conversation history is stored as a provider-neutral ledger.
- The ledger records user messages, assistant messages, tool calls, page snapshots, memory citations, approvals, run events, model choices, and model-switch events.
- Switching models appends an event; it does not rewrite canonical history.
- Each model adapter renders prompts from the same canonical ledger.
- When a target model has a smaller context window, the app creates an explicit summary artifact that remains linked to the source messages.
- Context compression is visible in run activity and must not silently discard approvals, memory denials, wallet decisions, or page-action history.
- Tool permissions and approval gates do not change just because the user changes models.

P0 implementation sequence:

1. Add `LLMConversationKit` with persistent conversations, messages, runs, model registry, and model-switch events.
2. Add provider-neutral context ledger and adapter-specific prompt rendering.
3. Add context-window accounting and explicit summary artifacts for smaller model windows.
4. Add `BrowserAutomationKit` with typed tab-scoped command/results.
5. Add DOM query extraction with strict payload caps and redaction.
6. Add typed page actions: click, type, focus, submit, scroll, navigate, wait, stop.
7. Add page snapshots for conversation context.
8. Replace single-result Copilot execution with streamed `CopilotRun` state.
9. Add cancellation and user takeover.
10. Meter credits only when model work happens.

Approval gates:

- Form submit.
- Downloads.
- Wallet signing or spend.
- Cross-origin navigation.
- Destructive or purchase-like clicks.
- Credential or password fields.
- Memory writeback.
- AFMarket settlement.

Issues: #50 through #58 and #72.

## Swift Recreation Of Rust-Only Functionality

Rust-only functionality must be recreated as Swift packages and integrated with `swift/dBrowser`.

| Legacy Rust/Tauri area | Swift replacement | Required integration |
| --- | --- | --- |
| `crates/gui` Tauri browser shell | Existing SwiftUI/WKWebView shell | Keep improving `swift/dBrowser` only |
| `crates/agent-core`, `crates/ai-agent` | `AgentRuntimeKit` and `LLMConversationKit` | Conversations, model switching, Copilot runs, approvals, ledger, tool routing, credits |
| `crates/ipfs`, `crates/p2p` | `DecentralizedContentKit` | IPFS/IPNS resolution and content verification |
| `crates/blockchain`, `crates/walletd` | `WalletPolicyKit` and `ChainTrustKit` | Wallet state, signing, broadcast, proof labels |
| `crates/btc-light`, `crates/eth-light` | chain-specific Swift light-client packages | Verified chain state in the runtime UI |
| `crates/afm-node`, `crates/afm-zkvm` | `AFMarketKit` plus external AFMarket node contracts | Pack install, dispatch, attestation, proof, settlement |
| `crates/updater` | `UpdateDistributionKit` | Signed/content-addressed update checks if needed |
| Rust telemetry/security helpers | `DiagnosticsKit` and Swift app policy | Local diagnostics and privacy controls |
| Tauri commands and TypeScript UI | SwiftUI views and Swift async clients | No Tauri command bridge in current product |

Do not keep dual product paths. The Rust code can be mined for behavior, contracts, fixtures, and tests, but the deliverable is Swift package code and Swift app integration. Reference Rust modules should be named from issues when they are useful, then treated as source material rather than runtime dependencies.

## Data And Trust Boundaries

| Boundary | Rule |
| --- | --- |
| Web content to app | `WKWebView` loads only allowed URL schemes. Future automation uses audited scripts only, never arbitrary model JavaScript. |
| Copilot to page | Typed commands, tab IDs, timeouts, redaction, approvals, and cancellation. |
| Copilot to memory | OpenMind access intent first; approved context only; blocked memory stays visible as a notice without hidden content. |
| Copilot to AFMarket | Pack, lease, dispatch, attestation, proof, and settlement states are visible. Mock states are labeled. |
| App to LLM | Conversation context is provider-neutral. Local MLX first where possible. Gateway calls carry selected/redacted context only. |
| App to chain | Light-client verified or explicitly labeled fallback. RPC fallback is transport, not trust. |
| App to wallet | Secure Enclave, WalletConnect, or policy-backed signing; spend and signature requests require explicit approval. |

## User Flows

Normal browsing:

1. User enters an HTTP/HTTPS address or search terms.
2. `BrowserURLResolver` normalizes the input.
3. `BrowserWebView` loads the URL through `WKWebView`.
4. Navigation updates flow back into Swift tab state.

Decentralized address:

1. User enters IPFS, IPNS, ENS, or compatible name.
2. Swift blocks direct WebKit loading for unsupported schemes.
3. `MobileRuntimeBridge` resolves through current gateway fallback.
4. Future `DecentralizedContentKit` and chain packages replace fallback with verified resolution.
5. UI labels the trust source.

LLM conversation:

1. User opens the LLM surface with or without an active tab.
2. User selects a model or keeps the current default.
3. App stores messages and selected context in the provider-neutral ledger.
4. App builds a page snapshot and access intent when browser context is attached.
5. BrIAn/OpenMind gates personal memory.
6. AFMarket routes to a runner pack when selected and available.
7. Local MLX or gateway model executes the approved prompt.
8. User may switch models at any point; the next turn is rendered from the same ledger.
9. Page actions, memory writes, downloads, wallet operations, and settlement require approval.
10. Run activity shows model, events, usage, trust state, and final output.

Memory writeback:

1. User explicitly asks to remember, correct, or save an event.
2. Swift creates a write proposal with source metadata.
3. BrIAn/OpenMind applies policy and step-up if needed.
4. The app records success, denial, or review-required state.

AFMarket task:

1. User selects or accepts an AFMarket runner pack.
2. Swift installs or verifies the pack through the configured node/market contracts.
3. Router selects an expert or pack.
4. Node dispatches and executes.
5. Attestation/proof/settlement states feed back to Copilot activity and wallet UI.

## Implementation Roadmap

P0: Swift shell and automation

- Keep `swift/dBrowser` as the only current app.
- Add the desktop-style LLM conversation UI and model-switching context ledger.
- Add `BrowserAutomationKit`.
- Add page snapshots and DOM actions.
- Add streamed Copilot runs, cancellation, approvals, and credit metering.
- Persist history, bookmarks, workflows, and run records locally.

P1: Memory, AFMarket, and local LLM

- Add `OpenMindMemoryKit` for BrIAn MCP.
- Add `AFMarketKit` for pack discovery, install, route, dispatch, proof, and settlement.
- Extract `BundledLLMKit` and wire real MLX inference for Gemma 4 E2B IT 4-bit.
- Add `LLMGatewayKit` for ZeroK/LLM Gateway calls.

P2: Decentralized trust

- Add `ChainTrustKit`.
- Add Bitcoin, Ethereum/EVM, Solana, Cosmos/Tendermint, Substrate, Avalanche, TRON, XRPL, Sui, and Aptos adapters.
- Replace IPFS/IPNS/ENS gateway fallback with verified Swift packages where possible.
- Add wallet signing with Secure Enclave, WalletConnect, or explicit external signer policies.

P3: Distribution and hardening

- Add signed/content-addressed updates if still needed.
- Add diagnostics export.
- Add UI tests around high-risk approval flows.
- Remove or archive legacy Rust/Tauri code once Swift parity is complete. Deprecated Rust/Tauri narrative documents live in `archive/deprecated-documents/`.

## Verification

Required validation for docs and Swift app changes:

```sh
git diff --check
LC_ALL=C grep -n '[^ -~]' docs/ARCHITECTURE.md docs/README.md README.md STATUS.md STRAWBERRY_SWIFT.md || true
xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'
xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests
```

Rust, pnpm, and Tauri commands are not current-product validation gates anymore. Run them only when mining or retiring legacy code.

## Documentation Policy

This file is the canonical architecture and plan. `docs/README.md` points here. Files under `docs/ai/` are supporting metadata for tools, not narrative documentation.

When architecture changes:

- Update this file first.
- Update linked GitHub issues when scope changes.
- Do not add parallel narrative docs.
- If a detail only applies to legacy Rust/Tauri code, label it as legacy or omit it.
