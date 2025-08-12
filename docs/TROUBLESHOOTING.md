# Troubleshooting Guide

This guide lists common issues when building and running the Browser project and how to fix them.

## Build and Tooling

- macOS: Install Xcode Command Line Tools
  ```bash
  xcode-select --install
  ```
- Rust toolchain issues
  ```bash
  rustup update
  cargo clean && cargo build -v
  ```
- Node/Tauri build issues
  ```bash
  pnpm install --frozen-lockfile
  pnpm run build
  ```

## Dev Server/Ports

- Avoid port 8080 on macOS (conflicts with Apple services). The project uses Vite on port 5173 by default.
  - If another process is using 5173, change it in `orbit-shell-ui/vite.config.ts` and `crates/gui/tauri.conf.json` consistently and update docs/scripts.
  - Kill the process holding the port:
    ```bash
    lsof -i :5173
    kill -9 <PID>
    ```

## Playwright / E2E Tests

- Ensure browsers are installed:
  ```bash
  npx playwright install --with-deps
  ```
- Run UI mode for debugging:
  ```bash
  pnpm --filter browser-gui run test:e2e:ui
  ```

## Rust Tests / GUI

- If GUI-related tests are flaky, run single-threaded and increase timeouts:
  ```bash
  cargo test -- --test-threads=1 --nocapture
  ```
- macOS permissions can block UI automation. Ensure Accessibility permissions for your terminal/IDE.

## IPFS/P2P Networking

- Port conflicts: IPFS API defaults to 5001, P2P to 4001 (see `.env` in `docs/DEVELOPMENT.md`). Adjust if occupied.
- Network blocked? Verify firewall settings allow local loopback and P2P UDP/TCP traffic.

## Common Cleanups

```bash
# Rust
cargo clean

# Node
rm -rf node_modules
pnpm install

# GUI build cache
rm -rf crates/gui/node_modules crates/gui/dist
pnpm --filter browser-gui install
```

## Logging

- Enable verbose logging:
  ```bash
  RUST_LOG=debug pnpm run dev
  ```
- Inspect Tauri logs at runtime; add temporary `println!`/`log` statements in Rust and `console.debug` in TS.

## Still Stuck?

- Open an issue using the appropriate template with logs and reproduction steps.
- Check `docs/DEVELOPMENT.md` and `README.md` for environment setup.
