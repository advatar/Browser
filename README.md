# dBrowser

dBrowser is now a native Swift browser and agent app. The current product lives under `swift/dBrowser`.

The old Rust/Tauri implementation remains useful as reference for behavior, contracts, fixtures, and tests, but it is not the current product architecture. Any capability that exists only in Rust must be recreated as a Swift package and integrated with the Swift app before it counts as supported.

## Current App

- SwiftUI shell: `swift/dBrowser/dBrowser/ContentView.swift`
- Browser state: `swift/dBrowser/dBrowser/BrowserViewModel.swift`
- Models and URL resolution: `swift/dBrowser/dBrowser/BrowserModels.swift`
- Web rendering: `swift/dBrowser/dBrowser/BrowserWebView.swift`
- Runtime bridge: `swift/dBrowser/dBrowser/RuntimeBridge.swift`
- AFMarket service client: `swift/dBrowser/dBrowser/AFMServicesClient.swift`
- Local MLX model selection: `swift/dBrowser/dBrowser/BundledLLM.swift`
- Tests: `swift/dBrowser/dBrowserTests/dBrowserTests.swift`

## Architecture

Read the canonical architecture and implementation plan:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

That document covers the Swift package migration plan, LLM conversation and page automation roadmap, AFMarket integration, BrIAn/OpenMind MCP memory, light clients, ZeroK/LLM Gateway, and validation commands.

The LLM target is a native desktop conversation surface similar in scope to Claude Desktop or ChatGPT Desktop. dBrowser differs by making model switching a first-class operation: the user can change the active LLM at any point while the app preserves a provider-neutral conversation ledger and renders context for the newly selected model.

## Validation

```sh
xcodebuild build -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS'
xcodebuild test -project swift/dBrowser/dBrowser.xcodeproj -scheme dBrowser -destination 'platform=macOS,arch=arm64' -only-testing:dBrowserTests
```
