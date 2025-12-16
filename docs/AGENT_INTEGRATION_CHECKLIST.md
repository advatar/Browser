# Agent + Marketplace Integration Checklist

This checklist tracks the end-to-end delivery of the Browser’s agent stack: MCP servers, Agent Apps, marketplace/AFM integration, and emerging agent-to-agent (A2A) surfaces. Keep statuses honest; prefer small, verifiable tasks.

## MCP & Copilot Foundation
- [x] Ship per-profile MCP manifests with validation on load/save (configs/mcp_profiles/*, UI settings)
- [x] Add “test connection” + tool refresh buttons in Settings → Model Context Servers
- [x] Ensure secrets flow through OS keyring (no plaintext writes) and round-trip via UI
- [ ] Telemetry: surface connection status + last tool list sync in UI
- [ ] Egress guardrails: defaultCapability + per-server capability prompts enforced at runtime

## Agent Apps (local workflows)
- [ ] Expand `configs/agent_apps.json` with at least 5 curated flows (research, wallet ops, automation, compliance, support)
- [ ] UI: Apps drawer cards show required capabilities + egress flags before launch
- [ ] Runtime: `launch_agent_app` enforces no-egress flags and MCP capability needs
- [ ] Persistence: last-run outputs + inputs stored per profile for quick relaunch
- [ ] Tests: cover registry load, validation, and launch-path happy/sad cases

## Marketplace & AFM Node Integration
- [ ] Embed marketplace UI route/tab in Tauri (crates/gui) with pack list + install actions
- [ ] Wire router/registry TypeScript clients into the GUI (shared client package)
- [ ] AFM controller service (Rust) starts/stops node sidecar and streams telemetry to GUI
- [ ] Task execution: submit pack runs via controller; show lease status and logs in UI
- [ ] Attestation + HPKE plumbing from Swift bridge → router policy checks
- [ ] Settlement: escrow status + payout approvals inside wallet UI
- [ ] Ops: pnpm/Make targets to boot router, registry, node, zkVM locally
- [ ] CI: smoke test covering router → node → proof → escrow submission (mocked chain OK)

## Agent-to-Agent (A2A) Surfaces
- [ ] Define protocol/transport for agent-to-agent quoting/execution (HTTP/MCP/A2A bus)
- [ ] Document capabilities + auth model (identity, rate limits, approvals)
- [ ] Add A2A tool(s) into agent toolchain with explicit capability prompts
- [ ] Telemetry: log and surface A2A requests/responses with provenance

## Release Gates
- [ ] Docs updated (USER_GUIDE, DEVELOPMENT, AFM integration) for new flows
- [ ] Tests green across Rust + pnpm workspaces
- [ ] Security review for key handling, attestation tokens, and egress controls
- [ ] Performance sanity: UI responsive with node/router running
- [ ] Feature toggles: ability to disable marketplace/AFM/A2A features per profile
