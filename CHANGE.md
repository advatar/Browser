### 🔄 Change-Request (CR-2025-10-14-A)  
**Title:** _Add Strawberry-grade “Self-Driving” Agent Layer to the Decentralised Browser_  
**Requested by:** Product & Research  
**Status:** Draft → Review  
**Target release:** v 1.2 (April 2026)  
**Priority:** High – strategic parity & differentiation  

---

#### 1  Why we need this change
* **User pull:** early-adopter interviews ask for “AI that does the clicks for me.”  
* **Competitive risk:** Strawberry’s public beta demonstrates UI-level agents with human-in-the-loop safety — feature gap vs. our roadmap (v1.1 stops at ZK-verified browsing).  
* **Strategic fit:** We can deliver the same UX _plus_ privacy, capability-scoped permissions, cryptographic audit logs, and portable WASM skills – differentiators impossible in Strawberry’s cloud-centric model.

---

#### 2  Scope -– what changes

| Area | New / changed component | High-level description |
|------|-------------------------|------------------------|
| **Runtime** | `agent-core` crate (Rust) | *Headless agent engine* embedding:<br>• DOM instrumentation layer (JS ↔ Rust) for click/scroll/type<br>• Plan-Act-Observe loop with tool registry<br>• Capability enforcement (+revocation) |
| **Models** | `llm-router` service | Provider-agnostic router (OpenAI, Anthropic, local WebGPU) with policy: **local-first** unless site override. Meters tokens for credits subsystem. |
| **Skills** | `skills/` WASM bundles | Signed, content-addressed skill packs (sales-lead, recruiter, extractor, assistant, research) equivalent to Strawberry companions. Distributed via the P2P extension store. |
| **UI/UX** | Agent bar + approval modals | New bottom-tab bar: pick companion, start/stop run, view live steps. Approval dialog before “impactful” ops (send email, submit form, tx broadcast). |
| **Safety** | Capability tokens + rate-limiter | Fine-grained caps: _click_, _type_, _navigate_, _email:send(max=3/day)_. Stored as UCAN-style JWTs, auto-revoked on tab close. |
| **Logging** | `agent-ledger` | Content-addressed event log of every step → pinned to IPFS; optional chain anchor every N steps. User can export or zero-knowledge-redact. |
| **Pricing** | Credit meter | Matches Strawberry tiers; counts prompt tokens **only when AI acts**. Store balance off-chain in encrypted wallet sub-key; top-up via Stripe (fiat) or crypto. |
| **Integrations** | OAuth bridge | Google Workspace connector (mail, calendar, sheets) _local-first_ caching; token never shared with model. |

---

#### 3  Out-of-scope (future / spins out)

* Mobile agents (iOS/Android)  
* Voice-driven agent control  
* Enterprise policy console (will be CR-2026-Q2)

---

#### 4  Deliverables & acceptance criteria

| # | Deliverable | Acceptance test / KPI |
|---|-------------|-----------------------|
| D1 | `agent-core` 0.1.0 crate | Unit tests simulate DOM and assert click/scroll events fire in correct order & respect caps. |
| D2 | Five pre-built skills | Run E2E spec:\_“Sales Sally finds 10 CFO emails on LinkedIn & writes to Sheet in ≤ 180 s with ≤ 2 approval prompts.”_ Pass on Linux & macOS. |
| D3 | GUI agent bar & modal | UX review + accessibility audit (tab-focus order, ARIA labels). |
| D4 | Capability framework | Attempt forbidden action → blocked & logged; revocation refreshes live. |
| D5 | Crypto audit log | SHA-256 root CID appears in sidebar; modifying local log invalidates root hash. |
| D6 | Metering & billing | 1 token prompt decrements balance; manual top-up restores; negative balance blocks new agent runs. |
| D7 | Privacy toggle | “No-egress mode” forces local LLM; sniffed network traffic shows **zero** prompt egress. |
| D8 | Docs & SDK | 10-page “Build a Skill” guide + TypeScript templates; internal hack-day dev builds a custom skill in < 4 h. |

---

#### 5  Impact analysis

* **Codebase:** +6 new crates, +1 Tauri window, ~20 % GUI surface grow.  
* **Security:** new attack surface (skill WASM, LLM prompts). Mitigation: capability whitelist, wasm-time sandbox, dependency audit at CI.  
* **Perf:** ~150 MB extra RAM when local Llama-2 7B running. Provide model-off fallback.  
* **Licensing:** LLVM/MLIR for WebGPU; check compatibility w/ MIT/Apache.  
* **Teams:** ⬆ need 2 FTEs (Rust agent runtime, front-end PT).  
* **Schedule:** adds **12 developer-weeks** on top of current v1.1 burn-down; pushes GA to April 2026.  

---

#### 6  High-level timeline (relative)

| Week | Milestone |
|------|-----------|
| W 0 | CR approved, branch cut `feature/agent-layer` |
| W 1–2 | Runtime scaffold (`agent-core`, DOM bridge) |
| W 3–4 | Capability tokens, ledger prototype |
| W 5–6 | `llm-router` w/ local Llama-cpp & OpenAI driver |
| W 7 | Credit meter & wallet hook |
| W 8 | First skill (“Extractor Ella”) passes test sheet flow |
| W 9–10 | Remaining four skills; Google Workspace connector |
| W 11 | GUI polish, approvals, accessibility |
| W 12 | Pen-test, privacy leak audit, docs freeze |
| W 13 | Beta cut ➜ Extension store publish |
| W 14 | Buffer / hardening |
| W 15 | Tag **v1.2.0-rc1** |
| W 16 | GA & IPFS CID pin; announce |

---

#### 7  Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| LLM policy leaks sensitive content | Med | High | Default _no-egress_; redaction; opt-in provider list |
| WASM skill escape | Low | High | Wasmtime nano-process, capability check at import |
| Credit fraud / replay | Med | Med | Signed meter writes; nonce; weekly off-chain recon |
| Schedule slip (skills complexity) | Med | Med | Build skills in parallel; reuse Dendrite examples |
| Legal (Google TOS) | Low | High | Review OAuth scope, respect Google Limited Use policy |

---

#### 8  Open questions

1. **Local model size** – do we ship 4 GB GGUF by default or lazy-download?  
2. **Audit log anchor** – Ethereum calldata vs. cheap L2 blob?  
3. **Credit pricing** – mirror Strawberry tiers exactly or introduce crypto option?  

---

#### 9  Approval matrix

| Role | Name | Action |
|------|------|--------|
| Product Lead | Lisa O. | ✅ / ❌ |
| Engineering Lead | Ken P. | ✅ / ❌ |
| Security | Maya S. | ✅ / ❌ |
| Finance | Ravi T. | ✅ / ❌ |
| Legal | Sofia H. | ✅ / ❌ |

---

When approved, this CR will supersede minor feature tickets and create an **Agent Layer epic** in Jira with child stories matching the deliverables above.
