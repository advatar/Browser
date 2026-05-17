Findings

  - High: agent wallet “broadcast” can be a false positive. crates/gui/src/agent/tools.rs:487 uses record_local_broadcast(...) || broadcast_signed_intent(...),
    so a successful local JSONL append prevents any network broadcast. The response still reports broadcasted: true.
  - High: spend evaluation mutates policy state. crates/gui/src/wallet_store.rs:252 increments daily_spent during evaluate_spend, and crates/gui/src/
    commands.rs:977 exposes this as an evaluation command. Previewing or failed spends can consume daily allowance.
  - High: the zkVM crate is only a stub. crates/afm-zkvm/src/lib.rs:98 writes JSON with a DefaultHasher checksum over paths, not a real SP1/RISC Zero proof or
    verifier. Do not treat current artifacts as ZK security.
  - Medium: README claims Ethereum/Bitcoin light clients, but crates/eth-light/src/main.rs:1 and crates/btc-light/src/main.rs:1 are hello-world stubs. That
    overstates current decentralization guarantees.
  - Medium: root npm scripts still target deprecated crates/gui frontend while Tauri builds orbit-shell-ui. Compare package.json:7 with crates/gui/
    tauri.conf.json:3. This can make local validation look green on the wrong UI path.
  - Medium: enabled MCP tools can be unguarded if defaultCapability is null. crates/gui/src/agent/mcp_client.rs:223 registers remote tools with
    client.capability(), and default configs use null capabilities.

  ZK Opportunities

  - Replace afm-zkvm with real proof generation and verification for AFM task settlement.
  - Extend crates/agent-core/src/ledger.rs:17 into “proof of compliant automation”: prove capability limits, approvals, and no-egress policy without exposing
    full browsing transcript.
  - Add wallet policy proofs: prove a spend is within per-tx/daily/chain limits without revealing full budget history.
  - Use Merkle/CID proofs for IPFS and ENS content integrity; reserve ZK for private browsing/history or private policy proofs.

  Better AI Use

  - Move from raw JSON prompting/parsing in crates/ai-agent/src/orchestrator.rs:308 to constrained decoding or structured tool calls.
  - Add local embeddings over page snapshots/history for semantic recall; current history has summaries/keywords but no vector memory.
  - Add per-tool egress labels, redaction, and approval policy for MCP tools before exposing them to autonomous runs.
  - Implement the automation bridge beyond macOS; crates/gui/src/webview_automation.rs:425 currently disables it on non-macOS targets.

  iOS Chances
  A Tauri/WKWebView iOS MVP is realistic: about 60-70% with a focused port. Tauri v2 explicitly supports iOS, and Tauri uses WebKit/WKWebView on iOS/macOS. The
  repo already has iOS icons, but it needs a mobile entry point refactor, iOS-specific webview automation, sandboxed storage/keychain work, and feature cuts
  around background IPFS/libp2p.

  Full desktop parity on iOS is harder: about 35-45%. The blockers are child-webview tab behavior, App Store review constraints, background downloads/networking,
  local node lifecycle, and AI automation support. A non-WebKit alternative browser engine route is low probability unless you qualify for Apple’s
  BrowserEngineKit entitlements, which Apple limits by region and requirements.

  Sources used for iOS/platform assessment: Tauri 2.0 (https://v2.tauri.app/), Tauri project structure (https://v2.tauri.app/start/project-structure/), Tauri we
  bview versions (https://v2.tauri.app/reference/webview-versions/), Apple BrowserEngineKit (https://developer.apple.com/documentation/browserenginekit), Apple
  alternative browser engines in the EU (https://developer.apple.com/support/alternative-browser-engines/).

  Validation passed:
  cargo test -p gui -p agent-core -p ai-agent -p afm-zkvm -p blockchain, npm --prefix orbit-shell-ui run test, and npm --prefix orbit-shell-ui run build.

  I committed the required STATUS.md tracking updates: bcbe940 and ac79eea. The pre-existing dirty submodule state remains untouched: orbit-shell-ui/
  package.json.

