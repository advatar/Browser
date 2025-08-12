# Contributing to the Browser Project

Thank you for your interest in contributing! This document outlines how to set up your environment, the workflow we use, and guidelines to help your contributions land smoothly.

## Ground Rules

- Be respectful and follow our [Code of Conduct](CODE_OF_CONDUCT.md).
- Prefer small, focused pull requests over large, sweeping changes.
- Keep the docs up-to-date with your changes.
- Add tests for new behavior and ensure all tests pass.
- Use Conventional Commits for commit messages.

## Getting Started

1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feat/short-description
   ```
2. Set up the development environment (see `docs/DEVELOPMENT.md`).
3. Run the project locally:
   ```bash
   pnpm install
   pnpm run dev
   ```
4. Run tests and linters:
   ```bash
   cargo test --workspace
   pnpm run test
   cargo fmt --check && cargo clippy -- -D warnings
   pnpm run lint && pnpm run typecheck
   ```

## Project Structure

- Rust workspace crates are in `crates/` (e.g. `blockchain/`, `p2p/`, `ipfs/`, `gui/`).
- Frontend (Tauri + TS) lives in `crates/gui/`.
- Docs are in `docs/`.

Refer to `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md` for details.

## Development Guidelines

- Rust: follow `rustfmt` and fix `clippy` warnings.
- TypeScript: keep ESLint clean; prefer explicit types.
- Add or update unit/integration/e2e tests as appropriate.
- Keep PRs atomic; include a clear description and rationale.

## Commit Style (Conventional Commits)

Examples:
- `feat(gui): add wallet connect dialog`
- `fix(p2p): handle disconnections during discovery`
- `docs: add troubleshooting guide`

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`, `build`, `ci`.

## Pull Request Checklist

- [ ] Tests added/updated and passing
- [ ] Docs updated (`README.md`, `docs/*` as needed)
- [ ] Lint and typecheck pass
- [ ] Linked issue (if applicable) and changelog entry (if maintained)

## Reporting Issues

Use GitHub Issues and include reproduction steps, expected/actual behavior, and environment details (OS, Rust, Node, Tauri versions). See our issue templates for guidance.

## Security

Please do not open public issues for security vulnerabilities. See the Security section in `README.md` for private disclosure instructions.

## Community

See `SUPPORT.md` for ways to get help and participate.
