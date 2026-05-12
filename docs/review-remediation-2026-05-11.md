# REVIEW.md Remediation

This note records the remediation for `REVIEW.md` from 2026-05-11.

## 1. Dynamic Code Or Shell Execution

Status: remediated.

- The `STRAWBERRY.md` guidance no longer recommends ad hoc JavaScript evaluation.
- Content navigation in `crates/gui/src/main.rs` now goes through an allowlisted `StaticContentScript` helper.
- The legacy `crates/gui/src/main.ts` shell no longer calls the unregistered `execute_script` command.
- Agent DOM automation still evaluates JavaScript on macOS, but selector/text inputs are JSON encoded before interpolation and output is decoded as JSON through the structured automation bridge.
- Shell execution remains only for explicit OS integration or user-configured MCP stdio servers:
  - `open` / `explorer` / `xdg-open` use static executables and pass the file path as an argument without a shell.
  - MCP stdio launches the configured program directly with `Command::new`; it does not invoke a shell.

## 2. Credential And Config Material

Status: audited.

- `CapabilityToken` in `crates/agent-core/src/capabilities.rs` is quota state, not a bearer credential.
- MCP header/env secrets are persisted through the platform keyring via `McpSecretStore`; profile files store secret identifiers/previews rather than plaintext once saved.
- Test fixtures and local development phrases are non-production material and must not be reused for release credentials.
- Production credentials remain out of git and are supplied through the platform keychain, CI secrets, or notarization environment variables described in `VALIDATE.md`.

## 3. Debug Or Insecure Transport Settings

Status: classified.

- `Cargo.toml` has `debug = true` only under `[profile.dev]`.
- `[profile.release]` sets `debug = false`, disables debug assertions, enables LTO, and uses one codegen unit.
- No wildcard CORS or disabled TLS verification setting was found in the reviewed runtime configuration.

## 4. HTML Injection Surfaces

Status: remediated.

- Remaining legacy UI HTML rendering now flows through `renderTrustedHtml`, which is the single DOM replacement boundary for trusted templates.
- Dynamic text inserted into those templates is escaped or allow-listed before rendering.
- Simple clears and icons use `replaceChildren` or `textContent`.
- Inline `onclick` handlers in the settings template were replaced with delegated `data-action` handlers.

## 5. Nested Manifest Ownership

Status: documented.

Canonical ownership is:

- Root Cargo workspace: Rust crates listed in root `Cargo.toml`.
- Runtime desktop app: `crates/gui` plus `orbit-shell-ui`.
- AFM web/service packages: `apps/afm-marketplace`, `services/router`, `services/registry`, and `services/pipelines`.
- Swift packages: `swift/Packages/AFMRunner` and `swift/Packages/AttestationKit`.

Use `VALIDATE.md` as the release gate. Avoid verifying only a nested package when a change crosses the runtime app boundary.

## 6. Package Manager Lockfiles

Status: documented by boundary.

- Root JavaScript metadata keeps both npm and pnpm surfaces because root scripts delegate the legacy GUI through npm and AFM workspace scripts through pnpm.
- `crates/gui` is the legacy Tauri placeholder frontend and is validated with npm.
- `orbit-shell-ui` is the active runtime frontend and is validated with npm.
- The AFM JavaScript workspace is listed in `pnpm-workspace.yaml` and uses pnpm for filtered workspace commands.

## 7. Runtime Failure Shortcuts

Status: remediated for review evidence and classified for the remaining broad scan.

- The review-evidence unwrap/expect calls in `crates/afm-node` and `crates/afm-zkvm` tests were converted to `Result`-returning tests.
- Existing production panics are treated as startup-fatal bootstrap failures, invariant serialization failures, or poisoned-lock failures.
- Remaining test unwraps/expect calls are assertion style and are not release runtime paths.
