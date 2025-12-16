# Development Guide

## Table of Contents

- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing](#testing)
- [Debugging](#debugging)
- [Performance](#performance)
- [Contributing](#contributing)

## Getting Started

### Prerequisites

Before you begin development, ensure you have the following tools installed:

```mermaid
graph LR
    subgraph "Required Tools"
        Rust[Rust 1.70+]
        Node[Node.js 18+]
        Git[Git]
        PNPM[pnpm]
    end
    
    subgraph "Optional Tools"
        Substrate[Substrate Node]
        Docker[Docker]
        VSCode[VS Code]
    end
    
    Rust --> Node
    Node --> Git
    Git --> PNPM
    
    PNPM -.-> Substrate
    Substrate -.-> Docker
    Docker -.-> VSCode
```

#### Installation Commands

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install Node.js and pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh

# Verify installations
rustc --version
node --version
pnpm --version
```

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/advatar/browser.git
cd browser

# Install dependencies
cargo build
pnpm install

# Run initial setup
pnpm run setup

# Start development
pnpm run dev
```

## Development Environment

### Recommended IDE Setup

#### VS Code Extensions

```json
{
  "recommendations": [
    "rust-lang.rust-analyzer",
    "tauri-apps.tauri-vscode",
    "bradlc.vscode-tailwindcss",
    "esbenp.prettier-vscode",
    "ms-vscode.vscode-typescript-next"
  ]
}
```

#### Settings Configuration

```json
{
  "rust-analyzer.cargo.features": "all",
  "rust-analyzer.checkOnSave.command": "clippy",
  "editor.formatOnSave": true,
  "typescript.preferences.importModuleSpecifier": "relative"
}
```

### Environment Variables

Create a `.env` file in the project root:

```bash
# Development configuration
RUST_LOG=debug
BROWSER_DEV_MODE=true
IPFS_API_PORT=5001
P2P_LISTEN_PORT=4001

# Optional: Blockchain endpoints for testing
SUBSTRATE_WS_URL=ws://localhost:9944
ETHEREUM_RPC_URL=http://localhost:8545
```

## Project Structure

### Workspace Organization

```mermaid
graph TB
    subgraph "Root Workspace"
        Root[browser-workspace]
    end
    
    subgraph "Core Crates"
        P2P[p2p]
        IPFS[ipfs]
        Blockchain[blockchain]
        GUI[gui]
    end
    
    subgraph "Light Clients"
        ETH[eth-light]
        BTC[btc-light]
        Walletd[walletd]
    end
    
    subgraph "Utilities"
        LibP2PCore[libp2p-core]
        LibP2PVendor[libp2p-core-vendor]
    end
    
    Root --> P2P
    Root --> IPFS
    Root --> Blockchain
    Root --> GUI
    
    Root --> ETH
    Root --> BTC
    Root --> Walletd
    
    Root --> LibP2PCore
    Root --> LibP2PVendor
```

### Crate Dependencies

```mermaid
graph TD
    GUI --> P2P
    GUI --> IPFS
    GUI --> Blockchain
    
    P2P --> LibP2PCore
    IPFS --> P2P
    IPFS --> LibP2PCore
    
    Blockchain --> Walletd
    Blockchain --> ETH
    Blockchain --> BTC
    
    ETH --> P2P
    BTC --> P2P
    Walletd --> P2P
```

### Directory Structure

```
browser/
├── crates/
│   ├── blockchain/          # Blockchain integration
│   │   ├── src/
│   │   │   ├── lib.rs      # Main library interface
│   │   │   ├── client.rs   # Substrate client
│   │   │   ├── wallet.rs   # Wallet management
│   │   │   ├── transaction.rs # Transaction handling
│   │   │   └── sync.rs     # Chain synchronization
│   │   ├── tests/          # Integration tests
│   │   └── Cargo.toml
│   │
│   ├── p2p/                # P2P networking
│   │   ├── src/
│   │   │   ├── lib.rs      # libp2p integration
│   │   │   ├── behaviour.rs # Network behavior
│   │   │   └── transport.rs # Transport configuration
│   │   ├── src/bin/
│   │   │   └── main.rs     # P2P daemon
│   │   └── Cargo.toml
│   │
│   ├── ipfs/               # IPFS implementation
│   │   ├── src/
│   │   │   ├── lib.rs      # IPFS node
│   │   │   ├── bitswap.rs  # Bitswap protocol
│   │   │   └── storage.rs  # Block storage
│   │   └── Cargo.toml
│   │
│   └── gui/                # Frontend application
│       ├── src/            # TypeScript source
│       ├── src-tauri/      # Tauri backend
│       ├── public/         # Static assets
│       └── package.json
│
├── docs/                   # Documentation
├── src/                    # Main application
├── target/                 # Build artifacts
├── Cargo.toml             # Workspace configuration
└── package.json           # Node.js workspace
```

## Development Workflow

### Branch Strategy

```mermaid
gitgraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Setup"
    
    branch feature/p2p-networking
    checkout feature/p2p-networking
    commit id: "Add libp2p"
    commit id: "Implement DHT"
    
    checkout develop
    merge feature/p2p-networking
    
    branch feature/ipfs-integration
    checkout feature/ipfs-integration
    commit id: "Add IPFS node"
    commit id: "Implement Bitswap"
    
    checkout develop
    merge feature/ipfs-integration
    
    checkout main
    merge develop
    commit id: "Release v0.1.0"
```

### Development Process

```mermaid
flowchart TD
    Start([Start Development]) --> Branch[Create Feature Branch]
    Branch --> Code[Write Code]
    Code --> Test[Run Tests]
    Test --> Lint[Run Linting]
    Lint --> Review{Self Review}
    
    Review -->|Issues Found| Code
    Review -->|Looks Good| Commit[Commit Changes]
    
    Commit --> Push[Push to Remote]
    Push --> PR[Create Pull Request]
    PR --> CICheck[CI Checks]
    
    CICheck -->|Failed| Code
    CICheck -->|Passed| CodeReview[Code Review]
    
    CodeReview -->|Changes Requested| Code
    CodeReview -->|Approved| Merge[Merge to Main]
    
    Merge --> End([Complete])
```

### Daily Development Commands

```bash
# Start development environment
pnpm run dev

# Run specific crate in development
cargo run -p p2p
cargo run -p blockchain

# Run tests continuously
cargo watch -x test
pnpm run test:watch

# Format and lint
cargo fmt
cargo clippy
pnpm run lint

# Build for production
cargo build --release
pnpm run build
```

### MCP Server Integration

The AI Copilot can now reach external Model Context Protocol (MCP) servers. You can manage remote
servers from **Settings → Model Context Servers** inside the browser UI (no more manual JSON
patching), or keep editing `configs/mcp_servers.json` directly if you prefer version control for the
manifest. The settings panel lets you enable/disable transports, edit headers/Env vars, and see
connection status at a glance.

> **New:** MCP manifests now live under `configs/mcp_profiles/` so every browsing profile keeps its
> own curated server list. The settings panel exposes a profile selector plus Import/Export actions
> so teams can share bundles without touching the filesystem.

> **Secrets:** Header and environment entries marked as “Secret” are stored in the OS keyring and
> never written to disk. The UI masks these values, lets you rotate them in place, and fetches them
> on demand via `read_mcp_secret` when you click Reveal.

```json
{
  "servers": [
    {
      "id": "demo-weather",
      "name": "Local Demo MCP",
      "endpoint": "http://127.0.0.1:7410/mcp",
      "enabled": true,
      "timeoutMs": 20000,
      "transport": "http",
      "headers": {
        "Authorization": "Bearer dev-token"
      }
    },
    {
      "id": "local-stdio",
      "name": "Local STDIO MCP",
      "transport": "stdio",
      "program": "./bin/mcp-server",
      "args": ["--stdio"],
      "env": {
        "API_KEY": "set-me"
      },
      "enabled": false
    }
  ]
}
```

- `transport` supports `"http"`, `"websocket"`, or `"stdio"`; stdio/websocket transports maintain
  persistent connections and react to `tools/listChanged` notifications automatically.
- Toggle `enabled` per server to control discovery.
- `headers` are optional and let you attach API keys or auth tokens to HTTP/WebSocket requests.
- `defaultCapability` (e.g. `"navigate"`) gates every tool from that server behind a runtime
  capability request.
- Tool descriptions are cached between agent runs and refreshed automatically whenever a server emits
  `tools/listChanged` (or after a short TTL for plain HTTP endpoints), so we no longer re-fetch on
  every invocation.

Changes applied through the UI write back to `configs/mcp_servers.json` and hot-reload the agent –
no restart required.

## Code Standards

### Agent Apps

- `configs/agent_apps.json` stores reusable workflows. Each entry mirrors the "OpenAI Apps" model:
  `instructions`, `promptTemplate`, `quickPrompts`, `heroColor`, and policy flags like `noEgress`.
- `AgentAppRegistry` (Rust) hot-loads that file and powers the toolbar's **Apps** launcher. The UI
  lets you pick a card, fire a quick prompt, and inspect the agent's final answer without leaving the
  browser.
- Use `invoke('list_agent_apps')` to show catalogs and `invoke('launch_agent_app', { request })` to
  kick off a templated agent run.
- See `docs/AGENT_APPS.md` for the research notes comparing this experience with OpenAI's upcoming
  Apps announcement.

### Rust Code Standards

#### Formatting and Linting

```toml
# .rustfmt.toml
max_width = 100
hard_tabs = false
tab_spaces = 4
newline_style = "Unix"
use_small_heuristics = "Default"
reorder_imports = true
reorder_modules = true
remove_nested_parens = true
edition = "2021"
```

#### Clippy Configuration

```toml
# Cargo.toml
[lints.clippy]
all = "warn"
pedantic = "warn"
nursery = "warn"
cargo = "warn"

# Allow some pedantic lints that are too strict
module_name_repetitions = "allow"
similar_names = "allow"
too_many_lines = "allow"
```

#### Code Organization

```rust
// Example module structure
//! Module documentation
//! 
//! This module provides...

use std::collections::HashMap;
use anyhow::{Result, anyhow};
use tokio::sync::RwLock;

// Re-exports
pub use self::client::Client;
pub use self::error::Error;

// Modules
mod client;
mod error;
mod utils;

/// Public struct documentation
#[derive(Debug, Clone)]
pub struct ExampleStruct {
    /// Field documentation
    pub field: String,
    /// Private field
    private_field: u32,
}

impl ExampleStruct {
    /// Constructor documentation
    pub fn new(field: String) -> Self {
        Self {
            field,
            private_field: 0,
        }
    }
    
    /// Method documentation
    pub async fn process(&self) -> Result<()> {
        // Implementation
        Ok(())
    }
}
```

### TypeScript Code Standards

#### ESLint Configuration

```json
{
  "extends": [
    "@typescript-eslint/recommended",
    "prettier"
  ],
  "rules": {
    "@typescript-eslint/no-unused-vars": "error",
    "@typescript-eslint/explicit-function-return-type": "warn",
    "prefer-const": "error",
    "no-var": "error"
  }
}
```

#### Code Organization

```typescript
// interfaces/types.ts
export interface ContentRequest {
  url: string;
  method: 'GET' | 'POST';
  headers?: Record<string, string>;
}

export type ContentResponse = {
  data: Uint8Array;
  contentType: string;
  status: number;
};

// services/contentService.ts
import { ContentRequest, ContentResponse } from '../interfaces/types';

export class ContentService {
  private cache = new Map<string, ContentResponse>();

  async fetchContent(request: ContentRequest): Promise<ContentResponse> {
    // Implementation
  }

  private async fetchFromIPFS(cid: string): Promise<Uint8Array> {
    // Implementation
  }
}
```

### Documentation Standards

#### Rust Documentation

```rust
/// Fetches content from IPFS using the provided CID.
/// 
/// # Arguments
/// 
/// * `cid` - The Content Identifier for the requested content
/// * `timeout` - Optional timeout for the request
/// 
/// # Returns
/// 
/// Returns a `Result` containing the content bytes on success, or an error.
/// 
/// # Examples
/// 
/// ```rust
/// use ipfs::IPFSNode;
/// 
/// let node = IPFSNode::new().await?;
/// let content = node.get_content("QmHash123", None).await?;
/// ```
/// 
/// # Errors
/// 
/// This function will return an error if:
/// * The CID is invalid
/// * The content is not found
/// * Network timeout occurs
pub async fn get_content(
    &self, 
    cid: &str, 
    timeout: Option<Duration>
) -> Result<Vec<u8>> {
    // Implementation
}
```

#### TypeScript Documentation

```typescript
/**
 * Manages peer-to-peer connections and content routing
 * 
 * @example
 * ```typescript
 * const p2p = new P2PManager();
 * await p2p.initialize();
 * const content = await p2p.fetchContent('QmHash123');
 * ```
 */
export class P2PManager {
  /**
   * Fetches content from the P2P network
   * 
   * @param cid - Content identifier
   * @param options - Fetch options
   * @returns Promise resolving to content data
   * @throws {NetworkError} When content cannot be retrieved
   */
  async fetchContent(
    cid: string, 
    options?: FetchOptions
  ): Promise<Uint8Array> {
    // Implementation
  }
}
```

## Testing

### Testing Strategy

```mermaid
pyramid
    title Testing Pyramid
    "E2E Tests" : 10
    "Integration Tests" : 30
    "Unit Tests" : 60
```

### Rust Testing

#### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tokio_test;

    #[tokio::test]
    async fn test_wallet_creation() {
        let wallet = Wallet::new();
        assert!(wallet.list_keys().is_empty());
        
        let keypair = wallet.create_key("test").unwrap();
        assert_eq!(wallet.list_keys().len(), 1);
        assert!(wallet.get_key("test").is_some());
    }

    #[test]
    fn test_transaction_signing() {
        let keypair = KeyPair::generate(KeyType::Sr25519).unwrap();
        let mut tx = Transaction::new(
            keypair.public_key(),
            AccountId::from([1u8; 32]),
            1000,
            0,
            0,
            Era::Immortal,
        );
        
        tx.sign(&keypair).unwrap();
        assert!(tx.verify());
    }
}
```

#### Integration Tests

```rust
// tests/integration_tests.rs
use browser_blockchain::*;
use test_utils::*;

#[tokio::test]
async fn test_full_transaction_flow() {
    let node = start_test_substrate_node().await;
    let client = SubstrateClient::new(test_config()).await.unwrap();
    
    // Wait for connection
    client.wait_for_connection().await.unwrap();
    
    // Create and submit transaction
    let tx = create_test_transaction();
    let hash = client.submit_transaction(tx).await.unwrap();
    
    // Verify transaction inclusion
    let block = client.wait_for_transaction(hash).await.unwrap();
    assert!(block.contains_transaction(hash));
    
    node.stop().await;
}
```

### TypeScript Testing

#### Unit Tests with Vitest

```typescript
// tests/contentService.test.ts
import { describe, it, expect, vi } from 'vitest';
import { ContentService } from '../src/services/contentService';

describe('ContentService', () => {
  it('should fetch content from IPFS', async () => {
    const service = new ContentService();
    const mockFetch = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]));
    
    service.fetchFromIPFS = mockFetch;
    
    const result = await service.fetchContent({
      url: 'ipfs://QmHash123',
      method: 'GET'
    });
    
    expect(result.data).toEqual(new Uint8Array([1, 2, 3]));
    expect(mockFetch).toHaveBeenCalledWith('QmHash123');
  });
});
```

#### End-to-End Tests with Playwright

```typescript
// tests/e2e/browser.spec.ts
import { test, expect } from '@playwright/test';

test('should load IPFS content', async ({ page }) => {
  await page.goto('/');
  
  // Enter IPFS URL
  await page.fill('[data-testid="address-bar"]', 'ipfs://QmHash123');
  await page.press('[data-testid="address-bar"]', 'Enter');
  
  // Wait for content to load
  await expect(page.locator('[data-testid="content"]')).toBeVisible();
  
  // Verify content is displayed
  const content = await page.textContent('[data-testid="content"]');
  expect(content).toContain('Expected content');
});

test('should create and sign transaction', async ({ page }) => {
  await page.goto('/wallet');
  
  // Create new wallet
  await page.click('[data-testid="create-wallet"]');
  await page.fill('[data-testid="wallet-name"]', 'test-wallet');
  await page.click('[data-testid="confirm-create"]');
  
  // Send transaction
  await page.click('[data-testid="send-transaction"]');
  await page.fill('[data-testid="recipient"]', '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY');
  await page.fill('[data-testid="amount"]', '1.0');
  await page.click('[data-testid="sign-and-send"]');
  
  // Verify transaction confirmation
  await expect(page.locator('[data-testid="tx-confirmation"]')).toBeVisible();
});
```

### Test Utilities

```rust
// tests/test_utils.rs
use std::time::Duration;
use tokio::process::Command;
use tempfile::TempDir;

pub struct TestSubstrateNode {
    process: tokio::process::Child,
    temp_dir: TempDir,
}

impl TestSubstrateNode {
    pub async fn start() -> Result<Self> {
        let temp_dir = TempDir::new()?;
        let mut cmd = Command::new("substrate");
        cmd.args(&[
            "--dev",
            "--tmp",
            "--ws-port", "9944",
            "--rpc-port", "9933",
        ]);
        
        let process = cmd.spawn()?;
        
        // Wait for node to start
        tokio::time::sleep(Duration::from_secs(3)).await;
        
        Ok(Self { process, temp_dir })
    }
    
    pub async fn stop(mut self) {
        let _ = self.process.kill().await;
    }
}

pub fn test_config() -> SubstrateConfig {
    SubstrateConfig {
        node_url: "ws://localhost:9944".to_string(),
        ..Default::default()
    }
}
```

## Debugging

### Logging Configuration

```rust
// Initialize logging
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

fn init_logging() {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();
}

// Use in code
use tracing::{info, warn, error, debug, trace};

#[tracing::instrument]
async fn fetch_content(cid: &str) -> Result<Vec<u8>> {
    info!("Fetching content for CID: {}", cid);
    
    match ipfs_get(cid).await {
        Ok(content) => {
            debug!("Successfully fetched {} bytes", content.len());
            Ok(content)
        }
        Err(e) => {
            error!("Failed to fetch content: {}", e);
            Err(e)
        }
    }
}
```

### Debug Tools

#### Network Debugging

```bash
# Monitor P2P connections
cargo run -p p2p -- --debug-peers

# IPFS debugging
RUST_LOG=ipfs=debug cargo run

# Blockchain client debugging
RUST_LOG=blockchain=debug,substrate=debug cargo run
```

#### Frontend Debugging

```typescript
// Debug service worker
if (import.meta.env.DEV) {
  window.debugP2P = {
    peers: () => p2pService.getPeers(),
    content: (cid: string) => p2pService.fetchContent(cid),
    stats: () => p2pService.getStats(),
  };
}
```

## Performance

### Profiling

#### Rust Profiling

```bash
# CPU profiling with perf
cargo build --release
perf record --call-graph=dwarf ./target/release/browser
perf report

# Memory profiling with valgrind
cargo build
valgrind --tool=massif ./target/debug/browser

# Benchmarking
cargo bench
```

#### Memory Management

```rust
// Use Arc for shared data
use std::sync::Arc;
use tokio::sync::RwLock;

type SharedState = Arc<RwLock<AppState>>;

// Avoid unnecessary clones
fn process_data(data: &[u8]) -> Result<Vec<u8>> {
    // Process without cloning
    data.iter().map(|&b| b.wrapping_add(1)).collect()
}

// Use streaming for large data
use futures::stream::{Stream, StreamExt};

async fn process_large_content<S>(stream: S) -> Result<()>
where
    S: Stream<Item = Result<bytes::Bytes>>,
{
    let mut stream = std::pin::pin!(stream);
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        // Process chunk without loading entire content
        process_chunk(&chunk).await?;
    }
    Ok(())
}
```

### Optimization Guidelines

1. **Async/Await**: Use async for I/O operations
2. **Zero-Copy**: Avoid unnecessary data copying
3. **Lazy Loading**: Load resources on demand
4. **Caching**: Cache frequently accessed data
5. **Connection Pooling**: Reuse network connections

## Contributing

### Pull Request Process

```mermaid
flowchart TD
    Fork[Fork Repository] --> Clone[Clone Fork]
    Clone --> Branch[Create Feature Branch]
    Branch --> Develop[Develop Feature]
    Develop --> Test[Write Tests]
    Test --> Document[Update Documentation]
    Document --> Commit[Commit Changes]
    Commit --> Push[Push to Fork]
    Push --> PR[Create Pull Request]
    PR --> Review[Code Review]
    Review --> Changes{Changes Requested?}
    Changes -->|Yes| Develop
    Changes -->|No| Merge[Merge to Main]
```

### Commit Message Format

```
type(scope): subject

body

footer
```

Examples:
```
feat(p2p): add Kademlia DHT implementation

Implement Kademlia distributed hash table for peer discovery
and content routing. Includes bootstrap node configuration
and periodic routing table maintenance.

Closes #123
```

```
fix(wallet): resolve transaction signing issue

Fix bug where transactions were not properly signed when using
Ed25519 keys. The issue was caused by incorrect message hashing.

Fixes #456
```

### Code Review Checklist

- [ ] Code follows style guidelines
- [ ] Tests are included and passing
- [ ] Documentation is updated
- [ ] No breaking changes without discussion
- [ ] Performance impact considered
- [ ] Security implications reviewed
- [ ] Error handling is appropriate

## Secure Updates

Binary releases are distributed over IPFS and must be signed before clients
apply them. The `updater` crate provides the client-side workflow:

```rust,ignore
use cid::Cid;
use ed25519_dalek::VerifyingKey;
use std::convert::TryInto;
use updater::{IpfsGatewayClient, UpdateStatus, Updater};

# async fn check_for_updates() -> updater::Result<()> {
let gateway = IpfsGatewayClient::builder().build()?;
let key_bytes: [u8; 32] = hex::decode(std::env::var("BROWSER_UPDATE_PUBLIC_KEY_HEX")?)
    .expect("valid hex")
    .try_into()
    .expect("32-byte key");
let verifying_key = VerifyingKey::from_bytes(&key_bytes).unwrap();
let updater = Updater::new(gateway, verifying_key);

let manifest_cid = Cid::try_from("bafy...manifest").unwrap();
match updater.check_for_update_str(env!("CARGO_PKG_VERSION"), &manifest_cid).await? {
    UpdateStatus::Available(update) => {
        let binary_path = std::path::Path::new("/usr/local/bin/browser");
        updater.download_and_apply(&update, binary_path).await?;
    }
    UpdateStatus::UpToDate => tracing::info!("Already on the latest release");
}
# Ok(())
# }
```

Publishing a release follows these steps:

1. Build the binary and compute its SHA-256 digest plus byte size.
2. Upload the binary to IPFS and record the resulting CID.
3. Populate an `UpdateManifest`, sign it with the offline Ed25519 release key, and add the JSON to IPFS.
4. Distribute the manifest CID through the canonical channel (e.g. ENS record, signed feed).
5. Clients verify the signature, validate the SHA-256 digest, and atomically swap the binary.

Set the following environment variables before launching the GUI so it can automatically
poll for releases using the new updater integration:

- `BROWSER_UPDATE_MANIFEST_CID` – CID of the signed manifest JSON.
- `BROWSER_UPDATE_PUBLIC_KEY_HEX` – hex-encoded Ed25519 verifying key (32 bytes).
- `BROWSER_UPDATE_GATEWAY` – optional HTTP(s) gateway base (defaults to `https://ipfs.io/`).
- `BROWSER_UPDATE_TARGET_PATH` – absolute filesystem path to the browser binary that should be replaced.

When running, the GUI emits an `update-status` Tauri event containing the most recent
`UpdateInfo`. The front-end listens for this event, displays a banner when new versions
are available, and can either download them manually or call the new `apply_update`
command (exposed through the updater banner) to atomically swap the binary. After a
successful install, the backend broadcasts an `update-applied` event so the UI can prompt
the user to restart.

This development guide provides the foundation for contributing to the decentralized browser project. Follow these guidelines to ensure code quality, maintainability, and project success.
