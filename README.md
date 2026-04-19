# 🌐 Decentralized Web Browser

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Rust](https://img.shields.io/badge/rust-1.70+-orange.svg)](https://www.rust-lang.org)
[![TypeScript](https://img.shields.io/badge/typescript-5.0+-blue.svg)](https://www.typescriptlang.org)
[![Build Status](https://github.com/advatar/browser/workflows/CI/badge.svg)](https://github.com/advatar/browser/actions)

A desktop browser built with Rust, Tauri, and a dedicated runtime UI, focused on privacy-first browsing and native decentralized protocol support. The current runtime resolves `ipfs://` and `ipns://` content through the embedded node, supports ENS resolution through a configurable RPC endpoint, and ships with release telemetry disabled by default.

## 🚀 Project Status

**Current Status: Production Hardening**

The codebase is in active hardening rather than "production ready". The supported runtime path today is the Rust/Tauri shell in `crates/gui` paired with the React UI in `orbit-shell-ui`, and the current work focuses on:

- Runtime-enforced navigation security checks
- Native page-load and tab-state events instead of timer-based UI state
- Background download execution with backend event updates
- Release logging and telemetry disabled by default unless explicitly enabled
- CI coverage centered on the supported runtime frontend instead of the broken legacy npm lane

📋 **Detailed Progress**: See [CHECKLIST.md](CHECKLIST.md) for the complete implementation checklist with technical details.

🎯 **Ready to Use**: Download the latest release from the [releases page](https://github.com/advatar/browser/releases) or build from source using the instructions below.

## 🎯 Vision

This project aims to create a browser that operates without any single point of failure, where:

- **Minimize centralized dependencies**: IPFS and IPNS content is served from the embedded node, while ENS resolution can use a configurable RPC endpoint when required
- **End-to-end verifiability**: Every byte is content-addressed (IPFS CID or blockchain Merkle proof) for offline verification
- **Local key sovereignty**: Wallet keys never leave the device; all signing happens locally or via hardware wallets
- **Privacy by design**: release telemetry is disabled by default, verbose runtime logging is opt-in, and tracker blocking is enforced at navigation time

## 🏗️ Architecture

```mermaid
graph TD
    subgraph Browser_Shell ["Browser Shell (Rust/Tauri)"]
        UI["Tabs | Address Bar | Wallet UI | Settings"]
    end
    
    subgraph Core_Services ["Core Services"]
        Renderer["Web Renderer"]
        Wallet["Wallet & Identity"]
    end
    
    subgraph P2P_Layer ["P2P Network Layer"]
        libp2p["libp2p Stack\n• Kademlia DHT\n• Gossipsub\n• QUIC/Noise"]
    end
    
    subgraph Blockchain_Nodes ["Blockchain Integration"]
        IPFS["IPFS Node\n(Bitswap)"]
        ETH["Ethereum Light Client"]
        BTC["Bitcoin Light Client"]
        Substrate["Substrate Client"]
    end
    
    UI --> Renderer
    UI --> Wallet
    Renderer --> libp2p
    Wallet --> libp2p
    libp2p --> IPFS
    libp2p --> ETH
    libp2p --> BTC
    libp2p --> Substrate
```

## ✨ Features

- **🔗 Native IPFS Integration**: Built-in IPFS node with Bitswap protocol for decentralized content retrieval
- **⚡ Multi-Blockchain Support**: Integrated light clients for Ethereum, Bitcoin, and Substrate-based chains
- **🔐 Secure Wallet Management**: Hardware wallet support with local key storage and signing
- **🌐 P2P Networking**: libp2p-based networking stack with Kademlia DHT and Gossipsub
- **🔒 Privacy-First Design**: Release telemetry/logging is opt-in, Tor remains optional, and the runtime favors local-first protocol handling
- **🎨 Modern UI**: Cross-platform desktop application built with Tauri and TypeScript
- **🧪 Comprehensive Testing**: Unit tests, integration tests, and end-to-end testing with Playwright

## 🛠️ Technology Stack

### Backend (Rust)
- **[Rust](https://www.rust-lang.org/)** 1.70+ - Systems programming language for performance and safety
- **[Tokio](https://tokio.rs/)** - Asynchronous runtime for concurrent networking
- **[libp2p](https://libp2p.io/)** 0.48+ - Modular peer-to-peer networking stack
- **[IPFS](https://ipfs.io/)** - InterPlanetary File System for decentralized storage
- **[Substrate](https://substrate.io/)** - Blockchain development framework
- **[sp-core](https://docs.rs/sp-core/)** - Substrate core primitives for cryptography
- **[anyhow](https://docs.rs/anyhow/)** - Error handling
- **[thiserror](https://docs.rs/thiserror/)** - Custom error types

### Frontend (TypeScript)
- **[Tauri](https://tauri.app/)** 2.0+ - Cross-platform desktop application framework
- **[TypeScript](https://www.typescriptlang.org/)** 5.0+ - Type-safe JavaScript for robust development
- **[Vite](https://vitejs.dev/)** - Fast build tool and development server
- **[Vitest](https://vitest.dev/)** - Unit testing framework
- **[Playwright](https://playwright.dev/)** - End-to-end testing framework
- **[ESLint](https://eslint.org/)** - Code linting and formatting

### Key Components

| Component | Technology | Purpose |
|-----------|------------|----------|
| **P2P Networking** | libp2p (Rust) | Peer discovery, multiplexing, encryption |
| **Content Storage** | IPFS with Bitswap | Decentralized content addressing and retrieval |
| **Blockchain Integration** | Substrate, Custom light clients | Multi-chain transaction and state verification |
| **Wallet Management** | sp-core, Hardware wallet APIs | Secure key management and transaction signing |
| **UI Framework** | Tauri + TypeScript | Cross-platform desktop interface |
| **Testing** | Cargo test, Vitest, Playwright | Comprehensive test coverage |

## 🚀 Quick Start

### Prerequisites

- **Rust** 1.70 or later ([Install Rust](https://rustup.rs/))
- **Node.js** 18+ and **pnpm** ([Install Node.js](https://nodejs.org/))
- **Git** for version control
- **Docker** (optional, for local devnet)

## 📥 Download

### Pre-built Installers

Download the latest release for your platform:

| Platform | Download | Size |
|----------|----------|------|
| **macOS** | [decentralized-browser-v0.1.0.dmg](dist/decentralized-browser-v0.1.0.dmg) | ~50MB |
| **Windows** | [decentralized-browser-v0.1.0.msi](dist/decentralized-browser-v0.1.0.msi) | ~45MB |
| **Linux (DEB)** | [decentralized-browser-v0.1.0.deb](dist/decentralized-browser-v0.1.0.deb) | ~40MB |
| **Linux (RPM)** | [decentralized-browser-v0.1.0.rpm](dist/decentralized-browser-v0.1.0.rpm) | ~40MB |
| **Linux (AppImage)** | [decentralized-browser-v0.1.0.AppImage](dist/decentralized-browser-v0.1.0.AppImage) | ~42MB |

**Checksums**: [SHA256 checksums](dist/checksums.txt) • **Signatures**: [GPG signatures](dist/signatures.asc)

### Build from Source

Alternatively, build from source using the instructions below:

### Installation

```bash
# Clone the repository
git clone https://github.com/advatar/browser.git
cd browser

# Install Rust dependencies
cargo build

# Install Node.js dependencies
pnpm install

# Build the GUI components
pnpm run build

### Local Ethereum devnet (Anvil)
For local wallet broadcasting and end-to-end spends, start the bundled Anvil devnet:
```bash
docker compose up -d anvil
export ADVATAR_ETH_RPC=http://localhost:8545
```
Agent wallet spends will sign and submit raw transactions to this devnet and also log to `~/.advatar/broadcasts.jsonl`.
```

### Running the Application

```bash
# Development mode with hot reload
pnpm run dev

# Build for production
cargo build --release

# Run tests
cargo test --workspace
pnpm run test
```

## 🏗️ Development Setup

### Project Structure

```
browser/
├── crates/
│   ├── blockchain/     # Substrate client and wallet management
│   ├── p2p/           # libp2p networking stack
│   ├── ipfs/          # IPFS node implementation
│   ├── gui/           # Tauri-based frontend
│   ├── eth-light/     # Ethereum light client
│   ├── btc-light/     # Bitcoin light client
│   └── walletd/       # Wallet daemon
├── src/               # Main application entry point
├── Cargo.toml         # Rust workspace configuration
└── package.json       # Node.js workspace configuration
```

### Development Workflow

1. **Backend Development** (Rust)
   ```bash
   # Run specific crate tests
   cargo test -p blockchain
   cargo test -p p2p
   
   # Check code formatting
   cargo fmt --check
   
   # Run clippy for linting
   cargo clippy -- -D warnings
   ```

2. **Runtime Frontend Development** (TypeScript)
   ```bash
   cd orbit-shell-ui
   
   # Start development server
   npm run dev
   
   # Run tests
   npm run test

   # Build the runtime bundle consumed by Tauri
   npm run build
   ```

3. **Integration Testing**
   ```bash
   # Run all tests
   cargo test --workspace
   
   # Run end-to-end tests
   pnpm run test:e2e
   
   # Generate test coverage
   pnpm run test:coverage
   ```

### Environment Setup

For blockchain integration tests, you may need a local Substrate node:

```bash
# Install substrate (optional, for integration tests)
cargo install --git https://github.com/paritytech/substrate substrate --tag v3.0.0

# Run local test node
substrate --dev --tmp
```

## 📚 Usage

### Basic Operations

```bash
# Start the browser
./target/release/browser

# CLI operations (when implemented)
browserctl --help
browserctl wallet create
browserctl ipfs pin <CID>
```

### Configuration

Configuration files are stored in:
- **Linux**: `~/.config/browser/`
- **macOS**: `~/Library/Application Support/browser/`
- **Windows**: `%APPDATA%\browser\`

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Process

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Code Standards

- **Rust**: Follow `rustfmt` and `clippy` recommendations
- **TypeScript**: Use ESLint configuration provided
- **Commits**: Use [Conventional Commits](https://conventionalcommits.org/)
- **Documentation**: Update relevant docs for new features

### Testing Requirements

- Unit tests for all new functionality
- Integration tests for cross-component features
- End-to-end tests for user-facing features
- Minimum 80% code coverage

## 📖 Documentation
  
- **[API Documentation](https://docs.rs/browser)** - Rust API docs
- **[Architecture Guide](docs/ARCHITECTURE.md)** - Detailed system design
- **[Development Guide](docs/DEVELOPMENT.md)** - Setup and contribution guide
- **[User Manual](docs/USER_GUIDE.md)** - End-user documentation
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and fixes

## 🐛 Bug Reports & Feature Requests
  
Please use [GitHub Issues](https://github.com/advatar/browser/issues) to:
- Report bugs with detailed reproduction steps
- Request new features with clear use cases
- Ask questions about usage or development

## 🤝 Support & Community
  
- Read our [Support Guide](SUPPORT.md) for help options
- Use [GitHub Discussions](https://github.com/advatar/browser/discussions) for Q&A and ideas
- See our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md)

## 🔒 Security

For security vulnerabilities, please email [security@yourdomain.com](mailto:security@yourdomain.com) instead of using public issues.

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 Browser Project Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 🙏 Acknowledgments

- **[libp2p](https://libp2p.io/)** - Modular peer-to-peer networking
- **[IPFS](https://ipfs.io/)** - InterPlanetary File System
- **[Substrate](https://substrate.io/)** - Blockchain development framework
- **[Tauri](https://tauri.app/)** - Cross-platform app framework
- **[Rust Community](https://www.rust-lang.org/community)** - Amazing ecosystem and support

---

**Built with ❤️ by the decentralized web community**
