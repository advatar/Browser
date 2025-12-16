Integration Plan

  - Establish shared architecture doc: catalogue Browser touchpoints (crates/ai-agent, services/llm-router, crates/
    blockchain, crates/gui, skills/manifest.json) against zk-afm-net-starter modules (Rust node, router, registry,
    contracts, zkVM, Swift bridges, marketplace UI). Decide which components live in-process with Tauri and which stay
    as sidecars; capture data/attestation/settlement flows, trust boundaries, and config surface before moving code.
  - Unify workspaces: bring zk-afm-net-starter/node, zkvm, and Swift packages into the Rust workspace (new crate such as
    crates/afm-node); add router/registry/pipelines/marketplace to the JS monorepo (pnpm workspaces). Align dependency
    versions (Tokio, tracing, serde, libp2p, Foundry toolchain) and set up shared .cargo/config, .env templates, and
    Makefile targets for building all services from the Browser root.
  - Adapt the AFM node for browser orchestration: wrap the node entry points (node/src/main.rs, HPKE, leases, telemetry)
    behind an async service registered with agent-core::runtime so the browser can start/stop it, feed tasks, and read
    gossip. Replace the node’s internal p2p bus with Browser’s crates/p2p primitives, reuse existing telemetry/logging
    plumbing, and expose task lifecycle via Tauri commands in crates/gui/src/commands.rs.
  - Bridge model execution/attestation: connect afm_bridge::run_model to the existing Apple Foundation model bridge in
    crates/ai-agent/foundation and map attestation token handling to services/llm-router policies. Fill the Swift stubs
    (swift/Packages/AFMRunner, AttestationKit) to call the real AFM/attestation APIs on macOS/iOS, then surface those
    capabilities through the Rust FFI layer consumed by the node.
  - Integrate routing & registry surfaces: fold the TypeScript router (router/src) and registry (registry/src) into
    the Browser services bundle; reuse shared schemas via a generated client package consumed by the GUI and Rust node.
    Wire router selection results into the Browser automation skill system (skills/manifest.json) so tasks pick experts
    via the router rather than static policies, and add health/config UI in crates/gui to administer router/registry
    endpoints.
  - Connect settlement to Browser wallets: extend crates/blockchain to include bindings for contracts/src/
    AFMZKEscrow.sol (abi generation, settlement submission, proof verification status). Hook this into the wallet
    UI (crates/gui/src/wallet_ui.rs) so users can fund escrows, monitor payouts, and approve submissions. Ensure key
    management aligns with the node’s payout address requirements and existing signer flows.
  - Finalize zkVM pipeline: choose SP1 or RISC Zero per zkvm/README.md, complete the program logic, and provide a host
    runner that the Rust node can call (possibly via Wasmtime or direct binary). Add deterministic tests for proof
    generation (zkvm/program, node/tests) and integrate artifacts into the settlement flow.
  - UI/UX integration: embed or reimplement the marketplace (afm-marketplace-starter/app) inside the Tauri frontend as a
    new view, enabling pack discovery, install-to-node actions, and status dashboards. Surface task queue state, leases,
    and proof submissions in the browser UI, leveraging existing React/Vue components in crates/gui.
  - Operationalize and test: create end-to-end scripts that spin up router, registry, node, zkVM host, and Browser app
    locally (Docker compose under ops/, plus CI jobs). Add integration tests spanning task routing → AFM execution →
    proof → escrow submission, with mocked chain + attestation. Document deployment paths (local dev, staging with Base
    Sepolia, production) in docs/ and update CHECKLIST.md milestones accordingly.

  Next steps (pick one to start): 1) Draft the architecture & dependency alignment document. 2) Prototype pulling the
  Rust node into the Browser workspace to surface immediate build gaps. 3) Spike the Tauri UI panel for monitoring AFM
  node status.
