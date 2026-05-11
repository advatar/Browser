# Code Review: dBrowser

Review date: 2026-05-11
Tracker: https://github.com/advatar/Tracker/issues/53
Scope: top-level app folder `dBrowser` and nested project manifests under this folder, excluding generated dependency/build directories such as `.git`, `node_modules`, `target`, `.build`, `dist`, and virtual environments.

## Executive Summary

- Overall risk from this sweep: **High**
- Findings by severity: High 1, Medium 6, Low 0
- Source footprint: 135 source files by extension scan (Rust 94, JavaScript 11, Shell 8, Swift 7, TypeScript 7, CSS 6, HTML 2)
- Test footprint: 14 test-like files detected
- CI footprint: 1 GitHub Actions workflow files detected
- Git posture: 1 changed/untracked paths before review generation
- Pattern scan budget used: 212 text/source files scanned

## Architecture Snapshot

Detected project and build surfaces:
- `Cargo.toml`
- `apps/afm-marketplace/package.json`
- `crates/afm-node/Cargo.toml`
- `crates/afm-zkvm/Cargo.toml`
- `crates/agent-core/Cargo.toml`
- `crates/ai-agent/Cargo.toml`
- `crates/blockchain/Cargo.toml`
- `crates/btc-light/Cargo.toml`
- `crates/eth-light/Cargo.toml`
- `crates/gui/Cargo.toml`
- `crates/gui/package-lock.json`
- `crates/gui/package.json`
- `crates/ipfs/Cargo.toml`
- `crates/p2p/Cargo.toml`
- `crates/updater/Cargo.toml`
- `crates/walletd/Cargo.toml`
- `docker-compose.yml`
- `package-lock.json`
- `package.json`
- `pnpm-workspace.yaml`

Nested manifest owners sampled:
- `.`
- `apps/afm-marketplace`
- `crates/afm-node`
- `crates/afm-zkvm`
- `crates/agent-core`
- `crates/ai-agent`
- `crates/blockchain`
- `crates/btc-light`
- `crates/eth-light`
- `crates/gui`
- `crates/ipfs`
- `crates/p2p`
- `crates/updater`
- `crates/walletd`
- `services/llm-router`
- `services/pipelines`
- `services/registry`
- `services/router`
- `swift/Packages/AFMRunner`
- `swift/Packages/AttestationKit`

Package scripts sampled:
- ``apps/afm-marketplace/package.json`: build, lint`
- ``crates/gui/package.json`: build, lint, test, test:coverage, test:e2e, test:e2e:ui, test:ui, typecheck`
- ``package.json`: build, lint, test, test:coverage, test:ui, typecheck`
- ``services/pipelines/package.json`: build, lint, test`
- ``services/registry/package.json`: build, lint, test`
- ``services/router/package.json`: build, lint, test`

Local instruction/status files:
- `AGENTS.md`
- `STATUS.md`

## Findings

### 1. [High] Dynamic code or shell execution needs input-boundary review

These APIs are legitimate in tooling, but they become high-risk when command strings or evaluated input can be influenced by users, files, networks, or model output. Scanner count: 1.

Evidence:
- STRAWBERRY.md:71 `You need a way to **run JS in the content webview AND get JSON back**. `eval()` alone won’t return values.`
### 2. [Medium] Potential credential/config material needs a focused secret audit

Names commonly used for credentials or sensitive tokens appear in app-owned files. Some hits may be fixtures or placeholders, but every example should be verified, documented as fake, or moved to secret management. Values are redacted here. Scanner count: 344.

Evidence:
- crates/agent-core/src/capabilities.rs:92 `struct CapabilityToken {`
- crates/agent-core/src/capabilities.rs:98 `impl CapabilityToken {`
- crates/agent-core/src/capabilities.rs:147 `/// Registry that stores capability tokens and tracks consumption.`
- crates/agent-core/src/capabilities.rs:150 `grants: HashMap<CapabilityKind, CapabilityToken>,`
- crates/agent-core/src/capabilities.rs:172 `self.grants.insert(kind, CapabilityToken:[REDACTED];`
- crates/agent-core/src/capabilities.rs:176 `if let Some(token) = self.grants.get_mut(&kind) {`
- crates/agent-core/src/capabilities.rs:177 `token.revoke();`
- crates/agent-core/src/capabilities.rs:182 `let Some(token) = self.grants.get_mut(&kind) else {`
### 3. [Medium] Broad CORS/debug or insecure transport settings need environment gating

Wildcard CORS, debug flags, or disabled TLS verification should be mechanically limited to local/dev environments. Scanner count: 1.

Evidence:
- Cargo.toml:34 `debug = true`
### 4. [Medium] HTML injection surfaces need sanitization review

Direct HTML insertion needs one sanitizer policy and regression tests around every untrusted content path. Scanner count: 13.

Evidence:
- crates/gui/src/main.ts:282 `tabBar.innerHTML = '';`
- crates/gui/src/main.ts:304 `historyList.innerHTML = '';`
- crates/gui/src/main.ts:409 `indicator.innerHTML = '🔒';`
- crates/gui/src/main.ts:413 `indicator.innerHTML = '⚠️';`
- crates/gui/src/main.ts:511 `panel.innerHTML = this.generateSettingsHTML();`
- crates/gui/src/main.ts:1272 `section.innerHTML = this.renderMcpSection();`
- crates/gui/src/main.ts:1639 `this.listEl.innerHTML = '<p class="mcp-kv-empty">Unable to load agent apps.</p>';`
- crates/gui/src/main.ts:1672 `this.listEl.innerHTML = '<p class="mcp-kv-empty">No agent apps configured yet.</p>';`
### 5. [Medium] Many nested project manifests increase ownership and verification complexity

This app folder contains many buildable surfaces. Document ownership and canonical verification commands so fixes do not verify the wrong package.

Evidence:
- Cargo.toml
- apps/afm-marketplace/package.json
- crates/afm-node/Cargo.toml
- crates/afm-zkvm/Cargo.toml
- crates/agent-core/Cargo.toml
- crates/ai-agent/Cargo.toml
- crates/blockchain/Cargo.toml
- crates/btc-light/Cargo.toml
### 6. [Medium] Multiple JavaScript package-manager lockfiles are present

Mixed package managers make installs non-reproducible and can cause CI/local dependency drift. Pick one package manager per app boundary or document nested ownership.

Evidence:
- crates/gui/package-lock.json
- crates/gui/pnpm-lock.yaml
- package-lock.json
- pnpm-lock.yaml
### 7. [Medium] Runtime failure shortcuts are common enough to deserve hardening

Force unwraps, panics, unwraps, expect calls, and fatal errors should be converted to typed errors around IO, persistence, parsing, and user-driven paths. Scanner count: 310.

Evidence:
- crates/afm-node/src/lib.rs:393 `.expect("controller launches");`
- crates/afm-node/src/lib.rs:399 `.expect("task accepted");`
- crates/afm-node/src/lib.rs:406 `.expect("gossip stored");`
- crates/afm-node/src/lib.rs:410 `controller.shutdown().await.expect("clean shutdown");`
- crates/afm-zkvm/src/lib.rs:222 `let tmp = tempdir().unwrap();`
- crates/afm-zkvm/src/lib.rs:225 `std::fs::create_dir_all(&program_dir).unwrap();`
- crates/afm-zkvm/src/lib.rs:228 `std::fs::write(&program_path, b"program").unwrap();`
- crates/afm-zkvm/src/lib.rs:229 `std::fs::write(&input_path, b"input").unwrap();`

## Testing and Build Posture

Detected tests:
- `crates/blockchain/tests/integration_tests.rs`
- `crates/blockchain/tests/test_utils.rs`
- `crates/gui/tests/history.test.js`
- `crates/gui/tests/integration_tests.rs`
- `crates/gui/tests/navigation-ui.spec.js`
- `crates/ipfs/src/bitswap/tests/circuit_breaker_tests.rs`
- `crates/ipfs/tests/bitswap_tests.rs`
- `crates/ipfs/tests/circuit_breaker_integration.rs`
- `crates/ipfs/tests/circuit_breaker_tests.rs`
- `crates/ipfs/tests/dht_tests.rs`
- `crates/ipfs/tests/modern_node_tests.rs`
- `crates/ipfs/tests/standalone_circuit_breaker.rs`

Detected CI workflows:
- `.github/workflows/ci.yml`

Inferred verification commands to standardize:
- JavaScript: run the owning package-manager install/build/test scripts from the relevant `package.json`.
- Rust: run `cargo test` or workspace-specific checks from each Cargo workspace root.
- Swift Package: run `swift test` from each package root.

## Review Limitations

- This was a broad static review across many local apps, not a full manual product walkthrough.
- Generated directories and dependency trees were pruned so findings focus on app-owned source.
- Secret-like values were not reproduced; examples are redacted or limited to path/line evidence.
- Pattern scanning is capped per app to keep the cross-repository sweep tractable; high-risk folders need focused follow-up review.

## Recommended Next Steps

1. Resolve every High finding first, especially secret material, tracked generated output, and dynamic execution paths.
2. Add or tighten the app's canonical CI workflow so build and tests run on every push.
3. Convert inferred build/test commands into documented commands in the app README or STATUS file.
4. Add smoke tests around app launch, persistence, API boundaries, and security-sensitive adapters.
5. Re-run this review after cleanup and replace this file with a human-reviewed release checklist.
