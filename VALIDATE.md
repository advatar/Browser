# Validate

## Unit + Lint

```bash
# Strict lint gate for production crates (must pass in CI)
cargo clippy -p gui -p blockchain -p ai-agent -p updater -p agent-core --all-targets

# Rust unit + integration tests for the GUI crate
cargo test -p gui

# Runtime frontend tests (native webview command path + bounds sync)
npm --prefix orbit-shell-ui ci
npm --prefix orbit-shell-ui run test

# Runtime frontend build (Vite)
npm --prefix orbit-shell-ui run build

# Legacy placeholder frontend still compiles
npm --prefix crates/gui run build

# UI automation regression for address bar submission
npm --prefix orbit-shell-ui run build
cd crates/gui
./node_modules/.bin/playwright test tests/navigation-ui.spec.js
./node_modules/.bin/playwright test
```

## DMG Packaging (macOS)

```bash
# Developer packaging (unsigned local build is allowed)
make dmg

# Production packaging (requires valid signature + notarization ticket)
make dmg-prod
```

## Manual Smoke

```bash
# Run the desktop app in dev mode
make dev
```

- In the address bar, try navigating to a URL containing a single quote (for example `https://example.com/?q='test'`) and confirm navigation works without console errors.
- Navigate to a normal site (for example `https://example.com`) and confirm the page renders inside the app (native content webview) without using an iframe.
- Navigate to `about:home` and confirm the internal homepage UI renders and the web content view is hidden.
- Enter a URL in the address bar (for example `https://google.com`) and open the Sidebar → History; verify a new history row appears.
- Open the same URL twice and verify the history row remains a single entry with updated visit count.
- Use the history row menu to remove an entry and confirm it disappears.
- Open 2-3 tabs with different sites, navigate within one tab, switch tabs, and confirm each tab preserves its own page/history state.
- Use Back, Forward, Reload, and Stop in the toolbar and confirm they affect the active native tab content.
- Resize the window and toggle the sidebar a few times and confirm the web content stays aligned with the content area.
- Open the Copilot/agent UI, ask it to inspect the active tab, and confirm the run emits live activity events before the final response arrives.
- While an agent run is active, press Stop and confirm the run finishes in a cancelled state instead of hanging indefinitely.
- Ask the agent to use `browser.dom_query` on a selector that exists on the active page and confirm the response contains live DOM matches from the real tab rather than the old “not available” error.
- Ask the agent for `browser.page_snapshot` and confirm the payload includes the current page URL, title, main text, links, buttons, and forms from the active native tab.
- Ask the agent to click, type, and scroll on a simple page (for example a local test form or `https://example.com` plus a searchable form page) and confirm the visible native tab changes accordingly.
- Run a short agent task with the local Foundation model path and confirm credits decrease even when the provider does not report token usage explicitly.

## Async Review

- Open `docs/KEYMEIN.md` and confirm the note still matches the repo state: `KeyMeIn` is present as a submodule but is not wired into the current Cargo or JavaScript workspaces.
