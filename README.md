# dBrowser

dBrowser is now a native Swift browser and agent app. The current product lives under `swift/dBrowser`.

The old Rust/Tauri implementation remains useful as reference for behavior, contracts, fixtures, and tests, but it is not the current product architecture. Any capability that exists only in Rust must be recreated as a Swift package and integrated with the Swift app before it counts as supported.

Deprecated Rust/Tauri planning and review documents have been moved to `archive/deprecated-documents/` and should not be used as active guidance.

## Current App

- SwiftUI shell: `swift/dBrowser/dBrowser/ContentView.swift`
- Browser state: `swift/dBrowser/dBrowser/BrowserViewModel.swift`
- Models and URL resolution: `swift/dBrowser/dBrowser/BrowserModels.swift`
- Web rendering: `swift/dBrowser/dBrowser/BrowserWebView.swift`
- Ad and tracker blocking: `swift/dBrowser/dBrowser/BrowserAdBlocker.swift`
- Runtime bridge: `swift/dBrowser/dBrowser/RuntimeBridge.swift`
- AFMarket service client: `swift/dBrowser/dBrowser/AFMServicesClient.swift`
- Local MLX model selection: `swift/dBrowser/dBrowser/BundledLLM.swift`
- Tests: `swift/dBrowser/dBrowserTests/dBrowserTests.swift`

## Architecture

Read the canonical architecture and implementation plan:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

That document covers the Swift package migration plan, LLM conversation and page automation roadmap, AFMarket integration, BrIAn/OpenMind MCP memory, light clients, ZeroK/LLM Gateway, and validation commands.

The LLM target is a native desktop conversation surface similar in scope to Claude Desktop or ChatGPT Desktop. dBrowser differs by making model switching a first-class operation: the user can change the active LLM at any point while the app preserves a provider-neutral conversation ledger and renders context for the newly selected model.

## Validation

```sh
xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'
xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests
```

## Local AFM Marketplace

The Swift app uses the local AFM marketplace on `127.0.0.1:4850` when it is running. Start it during local development with:

```sh
pnpm --filter @browser/afm-marketplace dev
```

The service exposes `/api/training-jobs`, `/api/packs`, and `/api/experts`. Local training jobs create deterministic adapter artifacts and can be published into marketplace runner-pack and peer-expert indexes. This is the local artifact and marketplace path; Apple Foundation Model weight export remains an adapter boundary for future runtime support.

Issue #168 adds the seller-side inference backend to this local service. Training requests may include an optional `commerce` object; omitted commerce is normalized to an explicit `free` policy. A `metered` policy prices authoritative total-token usage with integer `rateMinorUnitsPer1K`, `asset`, `assetDecimals`, `network`, `payTo`, and `minChargeMinorUnits` fields. Published experts advertise an HTTP runner URL derived from the configured public base URL.

Inference is a quote-then-execute flow. Clients first `POST /api/runners/:id/quotes`, then `POST /api/runners/:id/inferences` with the quote, the same committed inputs, and an `Idempotency-Key`. Metered requests also carry payment authorization bound to the quote. The service fails closed when an inference executor is unavailable, and metered quotes additionally require an injected synchronous token estimator using the same tokenizer as the executor. Metered execution stops before model work when payment is missing, mismatched, rejected, or no payment processor is configured. The injected executor must return authoritative prompt, completion, and total-token usage with tokenizer and usage-attestation metadata; final settlement uses that usage rather than a character-count estimate.

Completed runs produce privacy-preserving receipts that retain input/output, runner-profile, and manifest commitments rather than prompt or context text. Provider state is available through `GET /api/inferences/:id`, `GET /api/receipts/:id`, and `GET /api/provider/summary`; the full endpoint contract is documented in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#local-afm-seller-inference-backend-issue-168).

This is a backend integration slice, not a production inference business in a box. Quote creation receives the plaintext prompt and context so the configured tokenizer can price them; it is not the encrypted ZeroK gateway path. The repository does not bundle a production model host, tokenizer, usage-attestation verifier, receipt-signing key, or payment provider, and the local service does not yet provide public authentication, TLS termination, durable persistence, or a Swift seller configuration/receipts UI. Deployments must inject those provider boundaries, verify/sign the stored commitments, and add normal production perimeter controls before exposing a runner beyond a trusted local development environment.

## Local Decentralized Storage Handlers

The Swift app routes non-gateway decentralized storage URIs to localhost native adapter endpoints on ports `4881` through `4892`. The same repo-owned handler service also exposes live private-overlay adapter endpoints for managed Tor/Arti and I2P on ports `4893` and `4894`. Start it during local development with:

```sh
pnpm --filter @browser/storage-adapters dev
```

The service implements one handler contract for each registered storage protocol: Filecoin, Walrus, Iroh, Hypercore/Hyperdrive, Sia, Storj, Tahoe-LAFS, Autonomi, BitTorrent/WebTorrent, Ceramic, OrbitDB, and Radicle. Each handler validates the Swift adapter metadata, preserves locator and verification metadata, proxies only configured local protocol backends, and otherwise renders a precise local-backend-required page. The private-overlay harness validates Tor/I2P adapter metadata, checks local proxy reachability, and can run deterministic smoke fixture fetches through `DBROWSER_TOR_SOCKS_URL` / `DBROWSER_ARTI_SOCKS_URL` or `DBROWSER_I2P_HTTP_PROXY_URL` / `DBROWSER_I2P_HTTP_PROXY`.

BitTorrent/WebTorrent and the built-in VPN client are privacy-boundary features, not anonymity guarantees. The Swift app minimizes dBrowser-side traces for torrent transfer tabs and enforces local/private routing through loopback adapters and NetworkExtension-backed VPN profiles, but effective VPN/torrent privacy still depends on OS entitlements, the actual tunnel configuration, and the local adapter or torrent engine implementation.

Private-overlay browsing recognizes Tor onion services, I2P, Hyphanet/Freenet, ZeroNet, and Lokinet before search or HTTPS fallback and routes them only to local/private adapters. Runtime status now distinguishes configured, managed-launch-ready, running, reachable, blocked, misconfigured, and verified adapters. The managed runtime layer discovers and can launch local Tor/Arti and I2P router processes with loopback-only proxy boundaries and no dBrowser clearnet fallback policy, but adapter health must still verify before `.onion` or `.i2p` navigation proceeds. Tor/I2P adapters now have a live local smoke harness for proving fixture fetches through SOCKS5 or the I2P HTTP proxy without DNS, search, public gateway, or clearnet fallback; full dark-web protocol support still requires managed runtimes and live end-to-end smoke runs for every network.
