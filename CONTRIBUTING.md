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
2. Install Xcode and open the Swift project under `swift/dBrowser`.
3. Run the project locally:
   ```bash
   xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'
   ```
4. Run tests and linters:
   ```bash
   xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests
   ```

## Project Structure

- Current Swift app: `swift/dBrowser`.
- Current architecture docs: `docs/`.
- Historical Rust/Tauri reference material: `archive/deprecated-documents/` and legacy code under `crates/`.

Refer to `docs/ARCHITECTURE.md` for details.

## Development Guidelines

- Swift: follow the existing SwiftUI, model, and test patterns in `swift/dBrowser`.
- Add or update unit/integration/e2e tests as appropriate.
- Keep PRs atomic; include a clear description and rationale.

## Commit Style (Conventional Commits)

Examples:
- `feat(swift): add wallet connect dialog`
- `fix(browser): handle decentralized URL fallback`
- `docs: add troubleshooting guide`

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `perf`, `build`, `ci`.

## Pull Request Checklist

- [ ] Tests added/updated and passing
- [ ] Docs updated (`README.md`, `docs/*` as needed)
- [ ] Swift build and focused tests pass
- [ ] Linked issue (if applicable) and changelog entry (if maintained)

## Reporting Issues

Use GitHub Issues and include reproduction steps, expected/actual behavior, and environment details such as OS, Xcode version, and target platform. See our issue templates for guidance.

## Security

Please do not open public issues for security vulnerabilities. See the Security section in `README.md` for private disclosure instructions.

## Community

See `SUPPORT.md` for ways to get help and participate.
