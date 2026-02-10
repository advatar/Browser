# Validate

## Unit Tests

```bash
# Rust unit + integration tests for the GUI crate
cargo test -p gui

# Frontend unit tests (Vitest)
npm --prefix crates/gui test
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
