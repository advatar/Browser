# Decentralized Browser: Resume Plan

Updated: 2025-08-12T17:06:21+02:00

## Objective
- Fix Rust GUI tests and build the macOS DMG installer.
- Ensure frontend tests pass and avoid macOS port conflicts (no 8080; use repo-configured port).

## Current Status
- Shared library refactor done in `crates/gui/`:
  - `src/app_state.rs` introduced and re-exported via `src/lib.rs`.
  - `src/main.rs` now imports from the library crate modules.
- Remaining Rust failures are focused in `crates/gui/src/performance.rs`:
  - `MemoryMetrics` defines: `heap_used`, `heap_total`, `external`, `rss`, `array_buffers` (bytes).
  - `collect_memory_metrics()` incorrectly uses fields `used_mb`, `total_mb`, `process_usage_mb` and depends on `libc` (not in `Cargo.toml`).
- Frontend is in `orbit-shell-ui/`; Tauri v2 devUrl is configured; avoid port 8080 (repo currently uses 5173).
- DMG script `scripts/create-dmg.sh` expects binary `gui` and has been updated accordingly.

## Next Actions (today)
1. Fix memory metrics implementation
   - Replace platform-specific `libc` code in `crates/gui/src/performance.rs` with a cross‑platform `sysinfo`-based implementation.
   - Populate `MemoryMetrics` (bytes):
     - `rss` = process RSS bytes.
     - `heap_used` and `heap_total` = approximate using RSS (ensures tests see `heap_used > 0`).
     - `external` and `array_buffers` = 0 for now.
   - Clean up fallback code (no `if let Some(System::new_all())`).
   - Add dependency in `crates/gui/Cargo.toml`:
     - `sysinfo = "0.30"` (or latest compatible in workspace).

2. Re-run Rust tests
   - From repo root:
     - `cargo test -p gui`

3. Frontend dependencies and tests
   - From `orbit-shell-ui/`:
     - `pnpm install`
     - `pnpm test`

4. Build release app
   - From repo root or `crates/gui/`:
     - `cargo tauri build`
     - If not using the Tauri bundler: `cargo build --release -p gui`

5. Create DMG
   - From repo root:
     - `bash scripts/create-dmg.sh`
   - Verify the script bundles the built app/binary named `gui`.

6. Smoke test DMG
   - Install and launch the app.
   - Verify navigation, settings, and a few Tauri commands.
   - Confirm dev server port is not 8080.

## Validation Checklist
- [ ] All `cargo test -p gui` pass.
- [ ] `pnpm test` in `orbit-shell-ui/` pass.
- [ ] Release build completes.
- [ ] DMG generated and opens successfully.
- [ ] No references to port 8080 in active configs/docs.

## Notes
- Prefer port 5173 for dev; avoid 8080 on macOS.
- Integration tests assert `memory_usage.heap_used > 0`; ensure implementation satisfies this.
- If retaining platform APIs, add `libc = "0.2"` to `gui/Cargo.toml`, but a `sysinfo`-only path is preferred.

## Useful commands
```sh
cargo test -p gui -q
pnpm -C orbit-shell-ui i && pnpm -C orbit-shell-ui test
cargo tauri build
bash scripts/create-dmg.sh
```
