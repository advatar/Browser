# Decentralized Browser: Resume Plan

Updated: 2025-08-13T00:39:45+02:00

## Objective

- Finalize internal homepage integration at `about:home` across React UI, GUI, and Tauri.
- Ensure navigation defaults, normalize blanks to `about:home`, and exclude all `about:*` from history.
- Update tests and docs; surface Light Clients help in the app.

## Current Status

- React: `ContentArea.tsx` renders `HomePage` for `about:home`; normalization returns `about:home` for blank input.
- Store: default homepage set to `about:home`.
- Tauri: defaults use `about:home` for initial/current URL.
- GUI:
  - `crates/gui/src/index.html` new-tab defaults to `about:home`.
  - `crates/gui/src/js/navigation-manager.js` `goHome()` → `about:home`; handles all `about:*`.
  - `crates/gui/src/js/history-manager.js` ignores all `about:*` (done).
  - `crates/gui/src/js/tab.js` default URL updated to `about:home` (done).
  - `crates/gui/src/js/tab-manager.js` still defaults to `about:blank` (pending).
- Tests: `crates/gui/tests/integration_tests.rs` still uses `about:blank` in places (pending update).
- Docs: `docs/LIGHT_CLIENTS.md` exists; not yet surfaced in UI.

## Next Actions (today)
1. GUI defaults
   - Update `crates/gui/src/js/tab-manager.js` to default new tabs to `about:home`.
   - Verify all new-tab entry points (`index.html`, shortcuts) use `about:home`.
2. History hygiene
   - Ensure update pathways also ignore `about:*` (e.g., `updateHistoryItem()` behavior).
3. Navigation and rendering
   - Verify `goHome` and blank input normalization land on `about:home`.
   - Confirm `about:home` uses React `HomePage` (no iframe) and commands handle missing iframe.
4. Tests
   - Replace `about:blank` with `about:home` in `crates/gui/tests/integration_tests.rs` and any remaining references.
5. Help docs
   - Add an in‑app Help (dialog or route) to render `docs/LIGHT_CLIENTS.md`.
6. Docs
   - Update user docs to reflect `about:home`, defaults, and embedded light clients.
7. QA
   - Manual pass on tab creation, Home, back/forward, history, bookmarks.

## Validation Checklist
- [ ] New tabs open to `about:home` (all paths).
- [ ] `about:*` never recorded in history.
- [ ] `goHome` and blank inputs route to `about:home`.
- [ ] `integration_tests.rs` updated and pass.
- [ ] Help shows Light Clients doc in-app.
- [ ] No regressions in navigation/iframe handling.

## Notes
- Keep `about:blank` backward-compatible but deprecated; normalize to `about:home` in UX where applicable.
- Use `normalizeForGateway()` to preserve `about:*` URLs as-is.

