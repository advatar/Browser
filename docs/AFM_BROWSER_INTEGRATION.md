# Browser ↔ AFM Network Integration Architecture

This document captures the shared architecture decisions required to land the zk-afm-net-starter stack inside the Browser workspace. It catalogues the touchpoints between existing Browser crates (Rust, Tauri, services, skills) and the AFM node toolchain (Rust node, router, registry, contracts, zkVM, Swift bridges, marketplace UI). The goal is to lock in topology, data/attestation/settlement flows, trust boundaries, and configuration surfaces before code moves.

## Scope & Goals
- Provide a single view of how Browser components map to zk-afm-net-starter modules so teams can divide work without re-litigating ownership.
- Decide which services embed inside the Tauri process versus run as managed sidecars, including control APIs, lifecycle hooks, and telemetry plumbing.
- Describe the end-to-end flow for task routing → AFM execution → attestation → proof/settlement → wallet UX, highlighting required adapters.
- Enumerate trust boundaries and required controls (HPKE, attest tokens, signer handling, network ACLs).
- Specify workspace alignment work: shared Cargo workspace, pnpm workspaces, `.env` templates, `.cargo/config`, and Makefile/ops targets.

## Component Matrix

| Browser workspace area | Role today | zk-afm-net-starter module | Integration deliverable |
| --- | --- | --- | --- |
| `crates/agent-core` runtime + `crates/ai-agent` LLM bridges | Manages browser agents, DOM tools, and Foundation Model access | `node/src/main.rs`, HPKE stack, leases, telemetry | Introduce `crates/afm-node` that wraps the node entrypoints as an async service registered with `agent_core::runtime::AgentRuntimeBuilder`. The service exposes `start_task`, `feed_gossip`, and `shutdown` handles consumed via new Tauri commands in `crates/gui/src/commands.rs`. |
| `crates/p2p`, `crates/ipfs` | Provide Browser-native networking primitives | Node internal P2P bus | Replace the node’s bespoke P2P with `crates/p2p` types so both Browser agents and AFM node share identity, key management, and telemetry subscribers. |
| `services/llm-router` | Today routes LLM traffic and enforces prompt policies | `router/src`, `registry/src` | Import router + registry TypeScript projects into the Browser pnpm workspace. Generate a shared client package (OpenAPI/ts) so both the GUI and Rust node consume the same schema for expert/pack metadata. |
| `skills/manifest.json` | Declares automation skills and quotas | Router selection results | Extend the manifest to reference router-provided expert IDs. Add a background sync that updates skill policies from the registry so tasks select experts via router output instead of static JSON. |
| `crates/ai-agent/foundation` | Calls Apple’s Foundation models on macOS | `afm_bridge::run_model`, Swift AFMRunner + AttestationKit | Build a Rust FFI surface (`crates/afm-bridge`) that proxies the node’s `run_model` calls into the existing Foundation model client, forwarding attestation tokens back to `services/llm-router` so policies can be enforced/issued. Fill Swift packages under `swift/Packages/{AFMRunner,AttestationKit}` to call the real Apple APIs for macOS/iOS and expose C headers for Rust. |
| `crates/blockchain` + `crates/gui/src/wallet_ui.rs` | Wallet abstractions, signer UX | `contracts/src/AFMZKEscrow.sol`, settlement scripts | Generate ABI bindings (via `ethers::abigen!`) for the AFM escrow contracts and extend wallet flows so users can fund escrows, monitor proofs, and authorize settlement submissions directly from the Browser wallet UI. Tie signer requirements into the AFM node payout address config. |
| `crates/gui` (Tauri UI) | Browser chrome, wallet, telemetry views | `afm-marketplace-starter/app` | Embed marketplace UI as a new Tauri view/route. Provide pack discovery, install-to-node actions, lease health dashboards, and router/registry admin panes. |
| `docs/`, `Makefile`, `scripts/`, future `ops/` | Developer workflow | Docker Compose, CI orchestration | Author ops scripts that can spin up router, registry, AFM node, zkVM host, and the Browser app locally/CI to cover end-to-end testing. |

## Execution Topology & Process Placement

| Component | Placement | Lifecycle owner | Interfaces |
| --- | --- | --- | --- |
| Tauri Browser (`crates/gui`, `src/main.rs`) | In-process | `cargo tauri dev/build` | Tauri command handlers (`crates/gui/src/commands.rs`), `agent-core` runtime, wallet UI |
| AFM controller service (`crates/afm-node`, new) | In-process async task managed by `agent-core::runtime` | Browser runtime | Registers with `agent_core::runtime::AgentRuntimeBuilder`; exposes `start_node`, `stop_node`, `submit_task`, `lease_status` commands to Tauri |
| AFM Rust node (migrated from `zk-afm-net-starter/node`) | Managed sidecar (Rust binary) spawned by Tauri | AFM controller service | JSON-RPC or gRPC control channel over localhost; P2P over Browser `crates/p2p`; telemetry via `tracing` subscriber forwarded to GUI |
| Router + Registry (`router/src`, `registry/src`) | pnpm workspace services (Node.js) running as sidecars or remote endpoints | ops scripts / CI | REST/gRPC endpoints consumed by Browser, AFM node, and GUI admin panes |
| ZKVM host runner (`zkvm/host`, `zkvm/program`) | Separate binary invoked by node (via Wasmtime or direct exec) | AFM node | IPC channel for witness + proof artifacts; output stored in Browser storage for settlement |
| Swift bridges (`swift/Packages/AFMRunner`, `swift/Packages/AttestationKit`) | Embedded frameworks loaded by Rust via `unsafe extern "C"` FFI | AFM controller service / node | Provide `run_model`, `fetch_attestation`, `seal_hpke_session` APIs with attestation tokens piped back into Rust |
| Marketplace UI (`afm-marketplace-starter/app`) | Re-implemented or embedded view inside `crates/gui` (Tauri window/tab) | GUI team | Uses generated router client; surfaces pack install actions; streams node status over Tauri events |

**Process decisions**
1. **In-process with Tauri:** orchestration-only logic (start/stop node, pass tasks, display telemetry) so we retain a single window lifecycle. Heavy compute (node, zkVM) remain out-of-process to keep UI responsive.
2. **Sidecars:** Router/registry and zkVM host remain separate processes to preserve their Node.js/Rust toolchains and to let ops orchestrate distinct scaling tiers. They expose HTTP/gRPC endpoints secured by mTLS/API keys.
3. **FFI bridges:** Swift runtimes only exist on macOS/iOS so the Rust AFM controller dynamically loads the Swift package frameworks via `dlopen`/`tauri::path::resolve_resource`. On non-Apple platforms the AFM features are disabled or proxied through remote attestation services.

## Data, Attestation & Settlement Flows

### 1. Task routing & lease orchestration
1. User selects a pack or automation skill inside the GUI (new marketplace view in `crates/gui`) or triggers a Browser automation defined in `skills/manifest.json`.
2. `crates/gui/src/commands.rs` issues `start_afm_node` (if needed) and forwards the task to the AFM controller service, which calls into `agent_core::AgentRuntime`.
3. The runtime queries the router (`router/src`) via the generated client (shared between Rust and TypeScript) to fetch expert availability, lease pricing, and policy requirements. The registry provides deterministic metadata and signing keys for each pack.
4. The controller seeds the AFM node with the selected pack, attaches Browser-native `crates/p2p` keypairs, and opens the gossip feed so Tauri can render live status in the GUI dashboard.
5. `services/llm-router` enforces LLM policy/attestation requirements for any subsequent model invocations triggered by the pack, sharing state with the TypeScript router through a shared Redis/SQLite store (backed by ops scripts).

### 2. Model execution & attestation
1. When the AFM node needs to run a model, it invokes `afm_bridge::run_model` (ported into `crates/afm-bridge`) instead of the old in-node stub.
2. The bridge reuses the existing Apple Foundation client in `crates/ai-agent/foundation.rs`, but now routes calls through Swift `AFMRunner` / `AttestationKit` packages compiled under `swift/Packages`. These packages call Apple’s APIs, retrieve attestation tokens, and enforce HPKE key exchange for encrypted model outputs.
3. Attestation tokens and lease telemetry are shipped back through the Rust bridge to `services/llm-router`, which compares them against configured policies before allowing results to propagate.
4. The controller logs every request/response pair into `agent-core`’s ledger so the Browser can surface provenance hashes and store them for future settlement disputes.

### 3. Proof generation & settlement
1. The AFM node produces witness data for the zkVM program chosen per `zkvm/README.md` (SP1 or RISC Zero). The node writes the witness into a shared workspace directory and invokes the zkVM host runner (Wasmtime module or native binary).
2. Proof artifacts are submitted back to the AFM node, which uses `crates/blockchain` (extended with `AFMZKEscrow.sol` bindings) to stage settlement transactions.
3. `crates/gui/src/wallet_ui.rs` is updated to monitor escrow balances, pending payouts, and proof verification status. Users can approve submissions or fund new escrows via existing wallet flows.
4. Settlement status, proof hashes, and payout receipts are emitted as Tauri events so the UI and automation layers can display completion/failure in real time.

### 4. Router/registry administration & automation skills
1. Router and registry endpoints are embedded into the Browser services bundle so the GUI can surface health/config pages (new section under settings). Admin actions (adding packs, rotating keys) use the generated client library to avoid drift.
2. Automation skills defined in `skills/manifest.json` ingest router rankings so tasks automatically pick experts instead of static capability lists. Health/backoff data from the router feeds the skill planner to avoid degraded packs.

## Trust Boundaries & Controls

| Boundary | Assets | Controls |
| --- | --- | --- |
| Tauri UI / Browser process | User keys, wallet state (`crates/gui/src/wallet_ui.rs`), agent prompts | Runs sandboxed inside OS windowing; secrets stored via Tauri keyring; only exposes high-level commands to AFM controller; UI never touches raw attestation tokens. |
| AFM controller ↔ AFM node | Task payloads, gossip streams, leases, HPKE session material | Localhost RPC secured by mutual Ed25519 keys derived from `crates/p2p`; controller rotates HPKE keys per task; telemetry channel uses `tracing` with structured redaction. |
| AFM node ↔ Router/Registry/LLM Router | Expert metadata, attestation proofs, routing policy | Router/registry endpoints require API keys stored in `.env.router`; traffic goes over HTTPS with client certs; attestation tokens validated inside `services/llm-router`. |
| AFM node ↔ Swift bridge | Foundation model prompts, Apple attestation tokens | Rust only calls Swift FFI after verifying binary signature; Swift packages enforce entitlements and return signed attestation; tokens persisted in sealed storage awaiting settlement. |
| Node ↔ Blockchain | Escrow funds, payouts, proofs | Wallet keys derived via `crates/blockchain` keystore; settlement transactions require explicit GUI approval; proofs stored in immutable log for audits. |

## Configuration & Workspace Alignment

### Rust workspace
- Move `zk-afm-net-starter/node` and `zkvm` crates under `crates/afm-node` and `crates/afm-zkvm` (or similar) and add them to the root `Cargo.toml [workspace.members]`.
- Depend on the root `[workspace.dependencies]` versions already curated (`tokio 1.37.0`, `tracing 0.1.40`, `serde 1.0.217`, `libp2p 0.54.1`, `Foundry` tooling via `ethers 2.x`) to avoid duplicate resolver graphs.
- Introduce a shared `.cargo/config.toml` defining target-specific linker flags for macOS (needed by Tauri + Swift FFI) and cross-compilation settings for the node/zkVM binaries.
- Create a new `crates/afm-bridge` (Rust) that exposes safe wrappers for the Swift FFI plus structured error types so both the node and Browser agents can reuse the same binding.

### pnpm workspace / JS services
- Pull `router`, `registry`, `pipelines`, and `afm-marketplace-starter/app` into the repo under `services/` and `apps/`. Update `pnpm-workspace.yaml` so the Browser GUI, router, registry, and marketplace share dependencies.
- Generate a TypeScript client package (e.g., `@browser/afm-clients`) from the router/registry OpenAPI schema and publish it to the local workspace so both the GUI and Node.js services share request/response types.
- Align Node.js toolchains via `.nvmrc`/`.node-version` and add scripts (`pnpm dev:router`, `pnpm dev:registry`, `pnpm dev:marketplace`) that can be invoked from the Browser root.

### Shared configuration templates

| File | Purpose | Key entries |
| --- | --- | --- |
| `.env.browser` | Tauri + agent runtime | `AFM_ROUTER_URL`, `AFM_REGISTRY_URL`, `AFM_NODE_RPC`, `FOUNDATION_MODEL_POLICY`, `WALLET_DEFAULT_NETWORK` |
| `.env.afm-node` | AFM Rust node | `AFM_NODE_ID`, `HPKE_SEED`, `P2P_LISTEN_MULTIADDR`, `ZKVM_HOST_BIN`, `SETTLEMENT_CHAIN_RPC` |
| `.env.router` / `.env.registry` | TypeScript services | `DATABASE_URL`, `JWT_SECRET`, `ATTESTATION_REQUIRED`, `ROUTER_API_KEY`, `REGISTRY_SIGNER` |
| `.env.zkvm` | Proof host | `RISC_ZERO_PROVER_BIN` _or_ `SP1_PROVER_BIN`, `PROGRAM_PATH`, `SEPOLIA_RPC_URL` |
| `.env.swift` (per Xcode project) | AFMRunner / AttestationKit entitlements | `TEAM_ID`, `BUNDLE_ID`, `ATTESTATION_AUDIENCE`, `KEYCHAIN_GROUP` |

Template files live under `configs/examples/` and are copied via `scripts/bootstrap_afm.sh`.

### Build, ops, and CI surfaces
- Extend the root `Makefile` with `afm-node`, `router`, `registry`, `zkvm`, and `ops` targets (e.g., `make afm-node dev`, `make ops-up`). Each target should respect the shared `.env` templates.
- Add an `ops/compose.afm.yaml` that spins up router, registry, node, zkVM host, and a mocked chain (e.g., Anvil + attestation simulators). `make ops-up` should boot the entire stack for local testing.
- Set up CI workflows that run cargo tests for the new crates, pnpm tests for router/registry, and end-to-end smoke tests that cover task routing → AFM execution → proof → escrow submission with mocked attestation.
- Document deployment paths (local dev, staging on Base Sepolia, production) in `docs/DEPLOYMENT.md` and update `CHECKLIST.md` milestones with AFM-specific checkpoints.

## Immediate Next Actions
1. **Draft dependency alignment doc (this file)** – ✅ complete.
2. **Prototype adding `zk-afm-net-starter/node` + `zkvm` crates into the workspace** to uncover build gaps and verify Cargo version alignment.
3. **Spike the Tauri UI panel for AFM node monitoring** so we can exercise the new controller service and telemetry feeds early.
