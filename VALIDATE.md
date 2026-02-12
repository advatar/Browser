# Validate

## Unit Tests

```bash
# Rust unit + integration tests for the GUI crate
cargo test -p gui

# Frontend build (Vite)
npm --prefix orbit-shell-ui ci
npm --prefix orbit-shell-ui run build
```

## DMG Packaging (macOS)

```bash
# Produces dist/decentralized-browser-v<version>-<arch>.dmg
make dmg
```

## Manual Smoke

```bash
# Run the desktop app in dev mode
make dev
```

- In the address bar, try navigating to a URL containing a single quote (for example `https://example.com/?q='test'`) and confirm navigation works without console errors.
- Navigate to a normal site (for example `https://example.com`) and confirm the page renders inside the app (native content webview) without using an iframe.
- Navigate to `about:home` and confirm the internal homepage UI renders and the web content view is hidden.
- Open 2-3 tabs with different sites, navigate within one tab, switch tabs, and confirm each tab preserves its own page/history state.
- Use Back, Forward, Reload, and Stop in the toolbar and confirm they affect the active native tab content.
- Resize the window and toggle the sidebar a few times and confirm the web content stays aligned with the content area.
