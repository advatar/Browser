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

