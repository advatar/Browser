# dBrowser Documentation

The current documentation source of truth is:

- [Current Architecture And Plan](ARCHITECTURE.md)

dBrowser has transitioned to Swift completely. Older Rust/Tauri documentation has been consolidated into the canonical architecture only where it still describes behavior, contracts, fixtures, or tests that must be recreated as Swift packages.

The current LLM product target is a native desktop conversation surface with persistent context and mid-conversation model switching.

Supporting metadata:

- `docs/ai/dev_commands.yaml`
- `docs/ai/system_map.yaml`

Do not add new parallel narrative docs under `docs/`. Update `ARCHITECTURE.md` instead.
