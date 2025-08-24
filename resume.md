# Decentralized Browser: Resume Plan

Updated: 2025-08-23T23:51:45+02:00

## Objective

- Unblock and run the full test suite (Rust + Frontend) locally.
- Fix Rust build failure by installing system `protoc` to avoid `prost-build` vendored CMake path.
- Run Vitest unit tests and Playwright e2e (Vite dev server on 5173; avoid 8080).
- If green, build release and create macOS DMG.

## Current Status

- IPFS crate: Modern node integrated and tested. Legacy IPFS integration tests/examples gated behind `feature = "legacy"`. New modern tests added in `crates/ipfs/tests/modern_node_tests.rs`. `cargo test -p ipfs --all-targets` passes cleanly.
- Workspace: Full `cargo test --workspace` may still be blocked by `prost-build` invoking vendored CMake when `protoc` is missing (pending validation on this machine).
- Frontend: `crates/gui/package.json` has `vitest` and `playwright` scripts; `playwright.config.js` targets `crates/gui/tests/`.
- Dev server: Uses Vite on 5173 per preference (avoid 8080).

## Next Actions (today)
1. Install Protobuf compiler and point `PROTOC` to it (Apple Silicon likely):
   - `brew install protobuf`
   - `export PROTOC=/opt/homebrew/bin/protoc`
   - Verify: `which protoc && protoc --version`
2. Retry Rust tests: `cargo test --workspace`.
3. Install frontend deps: `pnpm install` (root workspace).
4. Run unit tests: `pnpm -C crates/gui test`.
5. Install Playwright browsers: `pnpm -C crates/gui exec playwright install`.
6. Start dev server (port 5173): `pnpm run dev`.
7. In another terminal, run e2e: `pnpm -C crates/gui run test:e2e` (or `test:e2e:ui`).
8. If green, build:
   - `cargo build --release`
   - `pnpm -C crates/gui build`
   - (macOS) `bash scripts/create-dmg.sh`

## Validation Checklist
- [ ] `protoc` present and used by `prost-build` (no CMake fallback).
- [ ] `cargo test --workspace` passes.
- [ ] `pnpm -C crates/gui test` passes.
- [ ] Playwright e2e passes against dev server on 5173.
- [ ] Tauri dev runs: `pnpm -C crates/gui tauri dev`.
- [ ] DMG builds successfully on macOS.

## Notes
- Port policy: avoid 8080; Vite dev server runs on 5173 as configured.
- Previous `about:home` integration tasks are archived below and will be revisited after tests are green.

---

## Secondary Focus: P2P/Node Integration (from `PLAN.md`)

- Configure the app to use the enhanced `P2PBehaviour` and new `Node` implementation.
  - Files: see `crates/*` per `PLAN.md` tasks 48–53 (re-export, cleanup, integration wiring).
- Verify integration with tests and sample runs.
  - Run workspace tests; add/adjust tests where needed to cover P2P/IPFS paths.

### Quick References (verified by search)
- `about:home` occurrences: 
  - GUI: `crates/gui/src/index.html`, `crates/gui/src/main.rs`, `crates/gui/src/main.ts`, `crates/gui/src/js/navigation-manager.js`, `crates/gui/src/js/tab.js`, `crates/gui/src/utils.ts`.
  - React UI: `orbit-shell-ui/src/components/content/ContentArea.tsx`, `orbit-shell-ui/src/components/content/HomePage.tsx`, `orbit-shell-ui/src/components/tabs/TabBar.tsx`, `orbit-shell-ui/src/components/dialogs/CommandPalette.tsx`, `orbit-shell-ui/src/lib/hooks/useBrowserStore.ts`, `orbit-shell-ui/src/lib/url.ts`.
- `tab-manager`: `crates/gui/src/js/tab-manager.js` (update default new-tab URL).

### Commands
- Environment prep:
  - `brew install protobuf`
  - `export PROTOC=/opt/homebrew/bin/protoc`  # Apple Silicon; use /usr/local on Intel

- Rust tests:
  - `cargo test --workspace`

- Frontend tests:
  - `pnpm install`
  - `pnpm -C crates/gui test`
  - `pnpm -C crates/gui exec playwright install`
  - `pnpm run dev`  # start Vite on 5173
  - `pnpm -C crates/gui run test:e2e`

- Build & package:
  - `cargo build --release`
  - `pnpm -C crates/gui build`
  - `bash scripts/create-dmg.sh`

### Operational notes
- Avoid port 8080 in dev tooling and docs; prefer existing defaults in config (e.g., Vite’s default 5173) per prior setup.

---

## IPFS Modernization (2025-08-23)

- __Implemented__
  - `Node::listen_addrs()` in `crates/ipfs/src/ipfs/node_modern.rs` using rust-ipfs `listening_addresses()`.
  - New modern integration tests: `test_listen_addrs` and `test_blockstore_put_get` in `crates/ipfs/tests/modern_node_tests.rs`.
  - Legacy integration tests and example gated behind `#![cfg(feature = "legacy")]`.
  - Cleaned warnings in tests.

- __Next__
  - Decide whether to re-enable CLI binaries or keep disabled.
  - Optionally add a 2-node test covering `connect(peer_id, addrs)`.
  - Run full workspace tests after ensuring `protoc` is installed.

