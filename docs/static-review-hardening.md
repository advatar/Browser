# Static Review Hardening Notes

This note records the follow-up audit for GitHub issue #6.

## DOM Injection Sinks

The legacy Tauri `crates/gui/src/main.ts` shell now avoids direct dynamic HTML injection for high-risk UI surfaces:

- Wallet status rendering uses DOM nodes and `textContent`.
- Bookmarks and history panels are rendered with DOM nodes and event handlers instead of interpolated `innerHTML` and inline handlers.
- Settings form values, agent app attributes, release-note links, and update URLs are escaped or allow-listed before rendering.
- Agent app accent colors are restricted to hex colors before being used in inline style attributes.

Remaining `innerHTML` usage in this file is limited to static templates or templates where dynamic values are escaped before insertion.

## Rust Panic And Unsafe Hotspots

Production Rust changes made during this pass:

- Replaced recoverable content-bounds `expect` with an explicit error path.
- Replaced wall-clock `duration_since(UNIX_EPOCH).unwrap()` uses in security checks with a safe helper that falls back to `0` if the system clock is invalid.
- Converted generated P-256 coordinate `unwrap()` calls in iProov key setup into explicit `anyhow` errors.

Remaining `unsafe` blocks are platform FFI boundaries:

- macOS Foundation bridge calls in `crates/ai-agent/src/foundation/foundation_macos.rs`.
- macOS WebKit JavaScript evaluation in `crates/gui/src/webview_automation.rs`.

Remaining panics are either test-only assertions, build-script failures that should fail the build, or startup-fatal configuration bootstrap failures that are logged by the installed panic hook.
