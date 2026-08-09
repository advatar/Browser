 Yes—but not as a wholesale replacement.

  Use DCN as the capability-market protocol and orchestration layer, while retaining dBrowser’s AFM marketplace as a provider/seller adapter.

  Why:

  - DCN already implements the difficult buyer-side semantics: capability requirements, admissibility-before-ranking, quotes, assignments, execution receipts, replay protection, durable
    lifecycle state, settlement, authority, and evidence.

  - dBrowser’s apps/afm-marketplace/src/main.mjs is narrower: local expert training/publishing and seller inference. It is in-memory and explicitly lacks production persistence,
    authentication, reconciliation, signing, and key management.

  - DCN is not presently a drop-in marketplace server. Its /Users/johansellstrom/dev/advatar/DCN/adapters/actum-compute/src/lib.rs maps AFMarket providers into DCN’s model; it does not replace
    provider execution, training, or catalog APIs.

  - DCN’s Swift package exposes Cognitive ABI capability types, but not the complete Actum Compute lifecycle currently implemented in Rust. Integration therefore needs either expanded Swift
    bindings or use of the DCN native bridge.

  - There is a small contract mismatch: DCN currently consumes AFMarket’s /v1/experts, while dBrowser exposes /api/experts.

  Recommended ownership:

  dBrowser UI, approvals, wallet
            ↓
  DCN CapabilityRequirement + local admissibility
            ↓
  DCN Actum Compute quote/job/assignment/receipt lifecycle
            ↓
  AFMarket adapter
            ↓
  dBrowser local AFM seller/training service or external providers

  So I would:

  1. Make DCN’s Actum Compute objects the canonical market contracts.
  2. Add a DCN adapter for dBrowser’s /api/experts, quote, and inference endpoints.
  3. Keep dBrowser’s training, publishing, local provider, and marketplace UI.
  4. Replace dBrowser’s duplicated quote/job/receipt state progressively with DCN lifecycle calls.
  5. Add Swift bindings for DCN’s Actum Compute lifecycle before changing the app-facing APIs.
  6. Avoid presenting this as production-ready until DCN’s remaining offer-availability semantics and dBrowser’s production provider boundaries are completed.

  Bottom line: adopt DCN as the market brain and protocol authority; keep dBrowser’s implementation as one marketplace/provider backend. Rewriting the local training and inference service
  inside DCN would discard useful functionality without solving the provider-runtime problem.
