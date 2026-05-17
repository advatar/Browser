# Advatar Browser Roadmap

This checklist aligns delivery with the vision of a single portal for web2, web3, and the agentic internet. Pull 1–2 items per track into each sprint.

## 1. Stabilize MCP Foundation

- [x] Add encrypted secrets storage + UI helpers for MCP headers/env vars.
- [x] Persist MCP manifests per profile and support import/export bundles.
- [ ] Collect per-server logs & latency metrics; show them inline + via toasts.
- [ ] Ship sample HTTP + STDIO MCP servers with one-click enablement.

## 2. Expand Agent Runtime & Tooling

- [ ] Bundle richer local tools (DOM automation, wallet ops, AFM hooks) with clear capability requirements.
- [ ] Implement a signed skill installer (YAML/MCP discovery) including validation UX.
- [ ] Show an approvals timeline and “why this tool” rationale in the Copilot panel.
- [ ] Run untrusted tools inside a sandbox (WASM or jailed subprocess).

## 3. Unify Browsing & Agent Views

- [ ] Introduce “agent tabs” that display reasoning, tool calls, and control handoffs.
- [ ] Pipe active tab context (URL, DOM, selections) into agent memory APIs.
- [ ] Support agent-initiated navigation gated by explicit user approvals.

## 4. Web3-First Experience

- [ ] Harden wallet storage (OS keychain + hardware wallet fallback).
- [ ] Add chain selector, RPC config UI, and ENS/IPFS defaults with permission prompts.
- [ ] Surface transaction simulations and signing history inside the browser chrome.

## 5. Distributed AI Fabric

- [ ] Teach the LLM router to blend local, AFM, and remote MCP models with policy overrides.
- [ ] Expose credit usage & routing decisions in the UI; allow per-task overrides.
- [ ] Emit telemetry proving when execution stayed local (privacy toggle aware).

## 6. Resilience & AFM Integration

- [ ] Turn the AFM node panel into a guided wizard (validation + log viewer).
- [ ] Provide automatic fallback between light client, AFM node, and remote RPC.
- [ ] Cache critical manifests/history so the browser remains usable offline.

## 7. Ecosystem & Tooling

- [ ] Publish an MCP developer kit (schema types, manifest lint, test harness).
- [ ] Launch a marketplace (Orbit Shell UI) for discovering/installing servers & skills.
- [ ] Add schema validation + linting to CI for external MCP/skill contributions.

---

**Cadence:** Continue sequencing work left-to-right, keeping security reviews and telemetry instrumentation as exit criteria for each shipped feature.
