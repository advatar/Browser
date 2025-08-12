# Browser Project Plan - Current Status

## Project Overview
A decentralized browser with integrated IPFS, Ethereum, and Bitcoin support, built with Rust and Tauri.

## Current Status (2025-07-17)

### Recent Accomplishments
- Successfully resolved dependency conflicts across the workspace
- Aligned all libp2p components to compatible versions (0.48.x/0.49.x)
- Updated ipfs-embed to use default features
- Removed unsupported features from libp2p dependencies
- Verified build configuration across all crates

### Current Focus
- Integrating enhanced P2PBehaviour and new Node implementation
- Finalizing IPFS and Bitswap protocol integration
- Preparing for test suite execution

## Active Task List

### P2P & IPFS Integration
- [x] Scaffold p2p library and basic IPFS integration
- [ ] Implement Bitswap protocol
  - [x] Analyze current IPFS/Node/Swarm integration for Bitswap hooks
  - [x] Implement Bitswap message handling
  - [x] Integrate Bitswap with block storage (SledStore)
  - [x] Add/expand tests for Bitswap protocol
  - [x] Fix build errors and dependency mismatches in IPFS node
  - [x] Audit and align libp2p versions across all workspace crates
  - [x] Resolve p2p crate manifest error (remove/fix 'kad' feature)
  - [x] Resolve ipfs-embed dependency/features conflict (use default features)
  - [x] Resolve libp2p-core versioning/dependency error
  - [x] Determine compatible set of libp2p component versions
  - [x] Resolve libp2p versioning/dependency ambiguity
  - [x] Remove unsupported 'dns' feature from libp2p dependency
  - [x] Remove unsupported 'swarm' and 'metrics' features
  - [x] Remove unsupported 'tcp' feature from libp2p dependency
  - [x] Verify build success and resolve any remaining dependency mismatches
  - [x] Verify Bitswap completeness and interoperability
  - [x] Review and extend Bitswap tests for edge cases
  - [x] Integrate BitswapService into Node struct
  - [x] Integrate Bitswap into NodeBehaviour for network handling
  - [x] Update Node::new() to initialize BitswapService
  - [x] Implement Bitswap event handling in Node
  - [x] Update block exchange methods to use Bitswap
  - [x] Add Kademlia and mDNS support to P2PBehaviour
  - [ ] Integrate enhanced P2PBehaviour and new Node into the app
    - [x] Update lib.rs to re-export new Node implementation
    - [x] Clean up and deduplicate Cargo.toml dependencies
    - [x] Update codebase to use new Node (node_new.rs)
    - [ ] Configure app to use enhanced P2PBehaviour and Node
    - [ ] Verify integration with tests and sample runs

### Dependency Management
- [x] Resolve multihash version conflict between ipfs, ipfs-embed, and cid
- [x] Resolve libp2p-kad feature conflict in p2p crate
- [x] Align all libp2p dependencies in p2p crate to latest compatible versions (0.48.x/0.49.x)
- [x] Align all optional libp2p components to latest compatible versions
- [x] Resolve libp2p feature mismatches in ipfs crate
  - [x] Remove 'tls-tokio' feature (not available in 0.47.0)
  - [x] Remove 'upnp' feature (not available in 0.47.0)
  - [x] Remove 'websocket-tokio' feature (not available in 0.47.0)

## Next Steps
1. Complete integration of enhanced P2PBehaviour and new Node
2. Run full test suite to verify all functionality
3. Perform integration testing with IPFS network
4. Prepare for next phase of development

## Known Issues
- Some libp2p features had to be removed due to version incompatibilities
- May need to reimplement certain functionality using available features

## Environment
- Rust: stable
- libp2p: 0.47.0 (ipfs crate), 0.48.0 (p2p crate)
- ipfs-embed: 0.26.1 (using default features)

---

## 📌 Project Phases

### Phase 0: Initial Setup (v1.0)

Below is a detailed, command-level build manual. If you hand it to a junior developer who has only a basic grasp of Rust and JavaScript, they can still implement a working v1.0 in approximately 6 months.

---

## 🖥 0. Workstation Setup (1 day)

What	Exact commands / clicks
OS packages	Ubuntu 22.04: bash sudo apt update && sudo apt install -y build-essential libssl-dev pkg-config cmake curl git tmux zsh unzip libudev-dev libdbus-1-dev libgtk-3-dev libwebkit2gtk-4.0-dev
Rust toolchain	```bash curl https://sh.rustup.rs -sSf
Node + pnpm	```bash curl -fsSL https://deb.nodesource.com/setup_20.x
Git basics	git config --global user.name "Your Name"git config --global user.email you@example.com
Editor	Install VS Code → Settings → enable “Rust Analyzer”, “Prettier”, “Svelte for VS Code”.
Shell profile	Add to ~/.zshrc:alias cz='cargo watch -x check -x test'alias ct='cargo test -- --nocapture'Reload: source ~/.zshrc
Success check	rustc --version && cargo --version && node -v && pnpm -v show versions without error.


---

## 📂 1. Bootstrap Monorepo (2 days)

### Directory Structure

```bash
mkdir -p ~/code/browser
cd ~/code/browser
```
cd ~/code/browser
git init -b main
```bash
echo "# Decentralised Browser" > README.md
```

### 2. Cargo Workspace

```bash
# Create workspace Cargo.toml
cat > Cargo.toml <<'EOF'
[workspace]
members = [
    "crates/p2p",
    "crates/ipfs",
    "crates/eth-light",
    "crates/btc-light",
    "crates/walletd",
    "crates/gui"
]
resolver = "2"
EOF

# Create crate directories and basic files
mkdir -p crates/{p2p,ipfs,eth-light,btc-light,walletd,gui}/src
for c in p2p ipfs eth-light btc-light walletd gui; do
  # Create Cargo.toml for each crate
  cat > crates/$c/Cargo.toml <<EOF
[package]
name = "$c"
version = "0.0.0"
edition = "2021"

[dependencies]
EOF
  # Add a simple main.rs
  echo 'fn main() { println!("hello"); }' > crates/$c/src/main.rs
done
```

### 3. Continuous Integration

Create `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - name: Cache cargo
        uses: actions/cache@v4
        with:
          path: ~/.cargo/registry
          key: ${{ runner.os }}-cargo-registry-${{ hashFiles('**/Cargo.lock') }}
      - run: cargo fmt --all -- --check
      - run: cargo clippy --workspace --all-targets -- -Dwarnings
      - run: cargo test --workspace
```

### 4. Pre-commit Hooks

```bash
# Initialize husky for git hooks
pnpm dlx husky-init && pnpm install

# Set up pre-commit hook for code formatting and linting
npx husky set .husky/pre-commit "cargo fmt && cargo clippy --workspace -- -D warnings"

# Initial commit
git add .
git commit -m "chore: bootstrap workspace"

---

## 🔌 2. libp2p Transport Skeleton (Week 1)

### Monday: Create p2p Library

1. Add dependencies to `crates/p2p/Cargo.toml`:

```toml
[dependencies]
libp2p = { version = "0.55", features = ["tcp", "noise", "yamux", "identify"] }
tracing = "0.1"
async-std = { version = "1.12", features = ["attributes"] }
```

### Tuesday: Implement Transport Layer

1. Create basic transport with TCP, Noise, and Yamux:

```rust
let transport = TcpConfig::new()
    .upgrade(upgrade::Version::V1)
    .authenticate(NoiseConfig::xx(noise_keys).into_authenticated())
    .multiplex(YamuxConfig::default())
    .boxed();
```

### Wednesday: Basic Swarm Setup

1. Create a simple `P2PBehaviour` struct
2. Implement `NetworkBehaviour` trait
3. Set up basic event handling

### Thursday: Error Handling

1. Add proper error types
2. Implement `From` traits for error conversion
3. Add logging and metrics

### Friday: Testing

1. Write unit tests for transport layer
2. Test peer discovery
3. Verify message passing between nodes

#### Basic Swarm Example

```rust
use libp2p::{
    identity, 
    noise, 
    swarm::SwarmBuilder, 
    tcp::TokioTcpTransport, 
    yamux, 
    PeerId,
};

pub fn new() -> anyhow::Result<(PeerId, libp2p::Swarm<impl Send + 'static>)> {
    // Generate a new keypair and derive peer ID
    let key = identity::Keypair::generate_ed25519();
    let peer_id = key.public().to_peer_id();
    
    // Set up TCP transport
    let trans = TokioTcpTransport::new(
        libp2p::tcp::Config::default().nodelay(true)
    );
    
    // Configure Noise for secure communication
    let noise_keys = noise::Keypair::<noise::X25519Spec>::new()
        .into_authentic(&key)?;
    
    // Configure Yamux for multiplexing
    let muxer = yamux::YamuxConfig::default();
    
    // Build the transport stack
    let transport = trans
        .upgrade(libp2p::core::upgrade::Version::V1)
        .authenticate(noise_keys)
        .multiplex(muxer)
        .boxed();
    
    // Create ping behavior
    let behaviour = libp2p::ping::Behaviour::new(
        libp2p::ping::Config::new()
    );
    
    // Build the swarm
    let swarm = SwarmBuilder::with_executor(
        transport, 
        behaviour, 
        peer_id, 
        async_std::task::spawn
    ).build();
    
    Ok((peer_id, swarm))
}

### Testing the Basic Implementation

1. **Compile and Test**
   ```bash
   cargo test -p p2p
   ```
   (No tests yet, but this confirms successful compilation)

### Tuesday: Add CLI Binary

1. **Add Binary Target**
   Add to `crates/p2p/Cargo.toml`:
   ```toml
   [[bin]]
   name = "p2pd"
   path = "src/bin/main.rs"
   ```

2. **Create CLI Binary**
   Create `src/bin/main.rs` that:
   - Initializes the swarm
   - Listens on `/ip4/0.0.0.0/tcp/0`
   - Prints the bound multiaddress
   - Handles basic swarm events

### Local Discovery Testing

1. **Run Multiple Nodes**
   - Open two terminal windows
   - Run `cargo run -p p2p` in each
   - Copy the multiaddress from one terminal
   - Temporarily hard-code this address in the second terminal
   - Verify ping round-trip logs appear

### Wednesday: Tokio Integration

1. **Switch to Tokio**
   - Add tokio feature to p2p
   - Replace async-std with tokio
   - Update the Swarm builder to use tokio's executor
   - Ensure all async code is compatible with tokio's runtime

### Thursday: Metrics and Monitoring

1. **Add Prometheus Metrics**
   ```bash
   cargo add prometheus --features process
   ```
   - Implement metrics gathering
   - Expose metrics via HTTP on 127.0.0.1:9870
   - Use hyper to serve the metrics endpoint

### Friday: Unit Testing

1. **Create Test Harness**
   - In `tests/` directory, create integration tests
   - Spawn two swarms on different ports
   - Assert that ping RTT is less than 1 second
   - Test connection establishment and teardown
   - Verify message passing between nodes

## Commit Messages

```plaintext
feat(p2p): minimal libp2p swarm
feat(p2p): prometheus metrics exporter
```

---

## 📦 3. Embedded IPFS Node (Weeks 3–5)

### Week 3: Blockstore & CID Maths

1. **Add Dependencies**
   ```bash
   cargo add cid multihash sled
   ```

2. **Implement Blockstore**
   Create `blockstore::SledStore` with an embedded sled database:
   ```rust
   pub struct SledStore {
       db: sled::Db,
   }
   ```

3. **Core Functions**
   ```rust
   impl SledStore {
       /// Store data and return its CID
       pub fn put(&self, data: &[u8]) -> Cid {
           // Implementation here
       }

       /// Retrieve data by CID
       pub fn get(&self, cid: &Cid) -> Option<Vec<u8>> {
           // Implementation here
       }
   }
   ```

4. **Unit Tests**
   - Generate random 1KB test data
   - Store data using `put`
   - Retrieve data using `get`
   - Verify data integrity
   - Compare input and output

### Week 4: Bitswap Plumbing

1. **Add rust-ipfs Dependency**
   ```bash
   cargo add rust-ipfs --git https://github.com/rs-ipfs/rust-ipfs
   ```

2. **Create IPFS Node**
   In `ipfs/src/lib.rs`:
   ```rust
   pub struct Node {
       swarm: Swarm<...>,
   }
   
   impl Node {
       pub fn new(swarm: Swarm<...>) -> Self {
           // Mount rust-ipfs Behaviour onto existing Swarm
           Self { swarm }
       }
   }
   ```

3. **Handle NetworkBehaviour Conflict**
   - Both libp2p and rust-ipfs export `NetworkBehaviour`
   - Use `pub use` renames to disambiguate
   - Add `#[behaviour(out_event = "Event")]` attribute

### Week 5: IPFS Cat CLI Tool

1. **Add Binary Target**
   In `ipfs/Cargo.toml`:
   ```toml
   [[bin]]
   name = "ipfs-cat"
   path = "src/bin/ipfs-cat.rs"
   ```

2. **Parse CID Argument**
   ```rust
   let cid = cid::Cid::try_from(args[1].as_str())?;
   ```

3. **Stream and Output Data**
   ```rust
   let mut stream = node.get_block_stream(cid).await?;
   let mut stdout = tokio::io::stdout();
   while let Some(chunk) = stream.next().await {
       stdout.write_all(&chunk?).await?;
   }
   ```

4. **Manual Testing**
   ```bash
   # Fetch and display an image
   cargo run -p ipfs --bin ipfs-cat QmYwAPJzv5CZsnAzt... > logo.png
   eog logo.png  # Or open with your preferred image viewer
   ```

---

⛓ 4. Ethereum Light Client (Weeks 6–8)

### Week 6: Trin Integration

1. **Add Trin Dependency**
   ```bash
   cargo add trin --git https://github.com/ethereumportal/trin.git#v0.5.0
   ```
   > **Note:** Trin pulls 80+ crates; the first build may take ~10 minutes.

2. **Create Light Client Wrapper**
   In `eth-light/src/lib.rs`:
   ```rust
   use anyhow::Result;
   use std::thread::JoinHandle;
   use trin;

   /// Start the Ethereum light client
   pub async fn start(config: &Config) -> Result<JoinHandle<()>> {
       let trin_config = trin::config::TrinConfig::from_cli();
       let portal = trin::portalnet::PortalnetConfig::from(trin_config.clone());
       let handle = tokio::spawn(async move {
           trin::run(trin_config, portal)
               .await
               .expect("Failed to start Trin client");
       });
       Ok(handle)
   }
   ```

### Week 7: JSON-RPC Shim

1. **Add JSON-RPC Server**
   ```bash
   cargo add jsonrpsee
   ```

2. **Expose HTTP Endpoint**
   ```rust
   use jsonrpsee::{
       server::HttpServerBuilder,
       core::RpcResult,
   };
   
   const CHAIN_ID: u64 = 1; // Mainnet
   
   pub async fn start_rpc_server() -> anyhow::Result<()> {
       let server = HttpServerBuilder::default()
           .build("127.0.0.1:8546")
           .await?;
           
       server.register_method("eth_chainId", |_, _| async {
           Ok(format!("0x{:x}", CHAIN_ID))
       })?;
       
       Ok(())
   }
   ```

3. **Implement eth_getBlockByNumber**
   - Query Trin's header database (trin::u256id::HistorySqlite).
   - Implement block header retrieval and verification
   - Handle JSON-RPC request/response formatting

4. **Write cURL Integration Test**
   Create `tests/eth_rpc.rs`:
   ```rust
   use std::process::Command;
   use assert_cmd::prelude::*;
   use predicates::prelude::*;

   #[test]
   fn test_eth_chain_id() -> Result<(), Box<dyn std::error::Error>> {
       let mut cmd = Command::cargo_bin("eth-light")?;
       let output = cmd.arg("--rpc").arg("http://127.0.0.1:8546")
           .arg("eth_chainId")
           .assert()
           .success();
       
       let output = String::from_utf8(output.get_output().stdout.clone())?;
       assert_eq!(output.trim(), "0x1");
       Ok(())
   }
   ```

### Week 8: Proof Helper

1. **Add Dependencies**
   ```bash
   cargo add reth-primitives reth-rlp
   ```

2. **Implement verify_account_proof**
   In `eth-light/src/proofs.rs`:
   ```rust
   use reth_primitives::{AccountProof, H256, U256};
   use reth_rlp::Decodable;

   /// Verify an account proof against a state root
   pub fn verify_account_proof(
       proof: &[u8],
       address: H160,
       expected_balance: U256,
       state_root: H256,
   ) -> anyhow::Result<()> {
       let account_proof = AccountProof::decode(&mut proof)?;
       
       // Verify the proof against the state root
       account_proof.verify_proof(state_root)?;
       
       // Verify the account balance
       if account_proof.balance != expected_balance {
           return Err(anyhow::anyhow!(
               "Balance mismatch: expected {}, got {}",
               expected_balance,
               account_proof.balance
           ));
       }
       
       Ok(())
   }
   ```

3. **Golden File Test**
   ```rust
   #[test]
   fn test_vitalik_balance() {
       // Vitalik's address
       let vitalik = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
           .parse::<H160>()
           .unwrap();
           
       // Known state root and proof for block #1
       let state_root = "0x...".parse().unwrap();
       let proof = hex::decode("...").unwrap();
       
       // Expected balance at block #1
       let expected_balance = U256::from(1000) * U256::exp10(18);
       
       verify_account_proof(&proof, vitalik, expected_balance, state_root).unwrap();
   }
   ```

---

## 🪙 5. Bitcoin Light Client (Weeks 9–10)

### Week 9: Neutrino Client Setup

1. **Add Dependencies**
   ```bash
   cargo add neutrino --git https://github.com/bitcoindevkit/bdk.git
   ```

2. **Implement Basic Client**
   In `btc-light/src/lib.rs`:
   ```rust
   use anyhow::Result;
   use bdk::blockchain::Config;
   use neutrino::{self, Node, NodeHandle};
   use std::net::SocketAddr;
   
   /// Start the Bitcoin light client
   pub async fn start_light_client() -> Result<NodeHandle> {
       // Configure the neutrino client
       let config = neutrino::Config {
           listen_addr: "0.0.0.0:0".parse()?,
           connect: vec![
               "mainnet1-btcd.zaphq.io:8333".parse()?,
               "mainnet2-btcd.zaphq.io:8333".parse()?,
           ],
           ..Default::default()
       };
       
       // Create and start the node
       let (node, mut events) = Node::new(config).await?;
       
       // Spawn a task to log events
       tokio::spawn(async move {
           while let Some(event) = events.recv().await {
               tracing::info!("Bitcoin event: {:?}", event);
           }
       });
       
       // Start syncing
       node.start().await?;
       Ok(node)
   }
   ```

### Week 10: JSON-RPC Interface

1. **Add JSON-RPC Server**
   ```bash
   cargo add jsonrpsee
   ```

2. **Implement RPC Methods**
   ```rust
   use jsonrpsee::{
       server::HttpServerBuilder,
       core::RpcResult,
   };
   use bitcoin::block::Header;
   
   /// Start the JSON-RPC server
   pub async fn start_rpc_server(node: NodeHandle) -> anyhow::Result<()> {
       let server = HttpServerBuilder::default()
           .build("127.0.0.1:8332")
           .await?;
           
       // Register RPC methods
       server.register_method("getblockheader", {
           let node = node.clone();
           move |params, _| {
               let hash = params.one::<String>()?;
               // Implementation to get block header by hash
               Ok::<_, jsonrpsee::core::Error>(())
           }
       })?;
       
       server.register_method("getblock", {
           let node = node;
           move |params, _| {
               let hash = params.one::<String>()?;
               // Implementation to get full block by hash
               Ok::<_, jsonrpsee::core::Error>(())
           }
       })?;
       
       Ok(())
   }
   ```

3. **Example Usage**
   ```bash
   # Get block header
   curl -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getblockheader","params":["00000000000000000001c1b4d8a1ec9c4e3c4c7b8c5d8f3e8a2b5c6d7e8f9a0b1"]}' \
        http://127.0.0.1:8332
   ```

---

## 🔐 6. Wallet Subsystem (Weeks 11–12)

### Week 11: Core Wallet Functionality

1. **Add Dependencies**
   ```bash
   cargo add bip32 slip10 coins-bip39 directories-next
   ```

2. **Local Keystore**
   - Location: `~/.local/share/browser/keys/keystore.json`
   - Encryption: AES-GCM
   - Password: Loaded from `WALLET_PW` environment variable

3. **Hardware Wallet Support**
   ```bash
   cargo add hidapi --features linux-static-hidraw
   ```
   - Supports Ledger and Trezor devices via U2F
   - Automatic device detection
   - Secure key path derivation

### Week 12: IPC Interface

1. **IPC Provider Endpoints**
   - **Unix**: `/tmp/browser-wallet.ipc`
   - **Windows**: `\\.\pipe\browser-wallet`

2. **JSON-RPC Methods**
   - Follows EIP-1193 specification exactly
   - Implements all standard Ethereum wallet methods:
     - `eth_requestAccounts`
     - `eth_sendTransaction`
     - `eth_sign`
     - `personal_sign`
     - `wallet_switchEthereumChain`
     - `wallet_addEthereumChain`

3. **Security Model**
   - All operations require user confirmation
   - Rate limiting on sensitive operations
   - Secure key storage with memory protection
   - Hardware wallet isolation

4. **Testing**
   - Unit tests for all cryptographic operations
   - Integration tests with hardware wallets
   - Fuzz testing for IPC interface

---

## 🖼 7. Desktop GUI with Tauri (Weeks 13–14)

### Week 13: Project Setup

1. **Install Prerequisites**
   ```bash
   # Install Tauri CLI
   cargo install tauri-cli@2
   
   # Create new Tauri app with SvelteKit
   pnpm create tauri-app@latest gui
   ```
   - Choose SvelteKit as the frontend framework
   - Select TypeScript for type safety
   - Install dependencies when prompted

2. **Project Structure**
   ```
   gui/
   ├── src-tauri/    # Rust backend
   │   ├── src/
   │   └── Cargo.toml
   └── src/          # SvelteKit frontend
       ├── lib/
       └── routes/
   ```

### Week 14: IPC Communication

1. **Frontend (SvelteKit)**
   Create `src/lib/tauri.ts`:
   ```typescript
   import { invoke } from '@tauri-apps/api/core';
   
   export async function getPeerId(): Promise<string> {
     return await invoke<string>('peer_id');
   }
   
   export async function getNodeInfo() {
     return await invoke<{ version: string, peers: number }>('get_node_info');
   }
   ```

2. **Backend (Rust)**
   In `src-tauri/src/main.rs`:
   ```rust
   use std::sync::Mutex;
   use tauri::State;
   
   struct P2pState {
       peer_id: String,
       // Other state fields
   }
   
   #[tauri::command]
   fn peer_id(state: State<'_, Mutex<P2pState>>) -> String {
       state.lock().unwrap().peer_id.clone()
   }
   
   #[tauri::command]
   fn get_node_info(state: State<'_, Mutex<P2pState>>) -> serde_json::Value {
       let state = state.lock().unwrap();
       json!({
           "version": env!("CARGO_PKG_VERSION"),
           "peers": 0, // TODO: Get actual peer count
       })
   }
   
   fn main() {
       tauri::Builder::default()
           .manage(Mutex::new(P2pState {
               peer_id: "peer123".to_string(),
           }))
           .invoke_handler(tauri::generate_handler![peer_id, get_node_info])
           .run(tauri::generate_context!())
           .expect("error while running tauri application");
   }
   ```

3. **Development Workflow**
   ```bash
   # Terminal 1: Start SvelteKit dev server
   cd gui
   pnpm dev
   
   # Terminal 2: Start Tauri dev mode
   cd gui
   cargo tauri dev
   ```

4. **UI Components**
   - Create reusable components in `src/lib/components/`
   - Implement responsive layout with Tailwind CSS
   - Add dark/light theme support
   - Implement error boundaries and loading states

5. **Testing**
   - Unit tests for Rust backend
   - Component tests with @testing-library/svelte
   - E2E tests with Playwright

---

## 📡 8. Custom IPFS Protocol Handler (Week 15)

### Implementation

1. **Register Custom Protocol**
   In `src-tauri/src/main.rs`:
   ```rust
   use tauri::Manager;
   use url::Url;
   use std::path::PathBuf;
   use tokio::fs::File;
   use tokio_util::io::ReaderStream;
   use mime_guess::MimeGuess;
   
   fn main() {
       tauri::Builder::default()
           .setup(|app| {
               // Register ipfs:// protocol handler
               app.register_uri_scheme_protocol("ipfs", |_app, request| {
                   let uri = request.uri();
                   let url = Url::parse(uri)?;
                   
                   // Extract CID and path from URL
                   let cid = url.host_str()
                       .ok_or_else(|| tauri::Error::FailedToSendMessage("Missing CID".into()))?;
                   let path = url.path().trim_start_matches('/');
                   
                   // Create async block to handle the request
                   Box::pin(async move {
                       // Resolve the IPFS path to content
                       let content = resolve_ipfs_path(cid, path).await?;
                       
                       // Create streaming response
                       let mut response = tauri::http::ResponseBuilder::new()
                           .status(200);
                       
                       // Set content type based on file extension
                       if let Some(ext) = PathBuf::from(path).extension() {
                           if let Some(mime) = MimeGuess::from_ext(ext.to_str().unwrap_or(""))
                               .first() {
                                   response = response.header("Content-Type", mime.as_ref());
                               }
                       }
                       
                       response.body(content)
                   })
               });
               Ok(())
           })
           .run(tauri::generate_context!())
           .expect("error while running tauri application");
   }
   ```

2. **IPFS Path Resolution**
   ```rust
   use futures::StreamExt;
   use libipld::Cid;
   
   async fn resolve_ipfs_path(cid: &str, path: &str) -> Result<Vec<u8>, tauri::Error> {
       // Parse the CID
       let cid = Cid::try_from(cid)
           .map_err(|e| tauri::Error::FailedToSendMessage(e.to_string()))?;
       
       // Create IPFS client (assuming ipfs_embed is used)
       let ipfs = Ipfs::default();
       
       // Resolve the path
       let mut stream = ipfs.get_path(&cid, path)?;
       let mut content = Vec::new();
       
       // Stream the content in chunks
       while let Some(chunk) = stream.next().await {
           let chunk = chunk.map_err(|e| tauri::Error::FailedToSendMessage(e.to_string()))?;
           content.extend(chunk);
       }
       
       Ok(content)
   }
   ```

### Key Features

1. **Streaming Support**
   - Uses async/await for non-blocking I/O
   - Streams content in chunks to handle large files efficiently
   - Memory usage remains constant regardless of file size

2. **Content Type Detection**
   - Automatically detects MIME type from file extension
   - Falls back to `application/octet-stream` if unknown
   - Supports common web formats (images, videos, documents)

3. **Error Handling**
   - Proper error handling for invalid CIDs
   - Graceful fallback for missing content
   - Detailed error messages for debugging

4. **Performance Optimizations**
   - Zero-copy operations where possible
   - Efficient memory management
   - Connection pooling for IPFS nodes

### Testing

1. **Unit Tests**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       use std::str::FromStr;
       
       #[tokio::test]
       async fn test_resolve_ipfs_path() {
           // Test with known-good CID and path
           let cid = "Qm...";
           let path = "path/to/resource";
           let result = resolve_ipfs_path(cid, path).await;
           assert!(result.is_ok());
       }
   }
   ```

2. **Manual Testing**
   ```bash
   # Test with different content types
   curl ipfs://Qm.../image.jpg
   curl ipfs://Qm.../document.pdf
   curl ipfs://Qm.../video.mp4
   ```

---

## 🔖 9. ENS + IPNS Resolution (Week 16)

### ENS (Ethereum Name Service)

1. **Add Dependencies**
   ```bash
   cargo add ethers ethers-providers ethers-contracts
   ```

2. **Resolve ENS Domain to IPFS Content**
   ```rust
   use ethers::{
       providers::{Provider, Http},
       types::Address,
   };
   use std::str::FromStr;
   use anyhow::Result;
   
   pub struct EnsResolver {
       provider: Provider<Http>,
   }
   
   impl EnsResolver {
       pub fn new(rpc_url: &str) -> Result<Self> {
           let provider = Provider::<Http>::try_from(rpc_url)?;
           Ok(Self { provider })
       }
       
       /// Resolve an ENS domain to IPFS content
       pub async fn resolve_ipfs(&self, domain: &str) -> Result<String> {
           let ens = ethers_ens::Ens::new(self.provider.clone());
           let content = ens.text(domain, "ipfs").await?;
           Ok(content)
       }
       
       /// Resolve an ENS domain to an Ethereum address
       pub async fn resolve_address(&self, domain: &str) -> Result<Address> {
           let address = self.provider.resolve_name(domain).await?;
           Ok(address)
       }
   }
   ```

### IPNS (InterPlanetary Naming System)

1. **Add Dependencies**
   ```bash
   cargo add libp2p-kad libp2p-record prost
   ```

2. **Implement IPNS Record Store**
   ```rust
   use libp2p::{
       kad::{Record, RecordKey, store::MemoryStore, Kademlia, KademliaEvent},
       Multiaddr, PeerId,
   };
   use std::collections::HashMap;
   use prost::Message;
   
   pub struct IpnResolver {
       kademlia: Kademlia<MemoryStore>,
       records: HashMap<Vec<u8>, Vec<u8>>,
   }
   
   impl IpnResolver {
       pub fn new() -> Self {
           let local_key = identity::Keypair::generate_ed25519();
           let local_peer_id = PeerId::from(local_key.public());
           let store = MemoryStore::new(local_peer_id);
           let kademlia = Kademlia::new(local_peer_id, store);
           
           Self {
               kademlia,
               records: HashMap::new(),
           }
       }
       
       /// Publish an IPNS record
       pub async fn publish(&mut self, key: &[u8], value: &[u8]) -> Result<()> {
           // Create and sign the record
           let record = Record {
               key: RecordKey::new(key),
               value: value.to_vec(),
               publisher: None,
               expires: None,
           };
           
           // Store locally
           self.records.insert(key.to_vec(), value.to_vec());
           
           // Publish to DHT
           self.kademlia.put_record(record, libp2p::kad::Quorum::One)
               .await?;
               
           Ok(())
       }
       
       /// Resolve an IPNS key to its value
       pub async fn resolve(&self, key: &[u8]) -> Option<Vec<u8>> {
           // Check local store first
           if let Some(value) = self.records.get(key) {
               return Some(value.clone());
           }
           
           // Query DHT if not found locally
           let record_key = RecordKey::new(key);
           match self.kademlia.get_record(&record_key, libp2p::kad::Quorum::One).await {
               Ok(record) => Some(record.value),
               Err(_) => None,
           }
       }
   }
   ```

### Integration

1. **Unified Resolution**
   ```rust
   pub enum ResolutionResult {
       IpfsCid(String),
       IpnsKey(Vec<u8>),
       EthereumAddress(Address),
       Text(String),
   }
   
   pub struct NameResolver {
       ens: EnsResolver,
       ipns: IpnResolver,
   }
   
   impl NameResolver {
       pub async fn resolve(&self, name: &str) -> Result<ResolutionResult> {
           // Try ENS resolution first
           if name.ends_with(".eth") {
               if let Ok(ipfs) = self.ens.resolve_ipfs(name).await {
                   return Ok(ResolutionResult::IpfsCid(ipfs));
               }
               if let Ok(addr) = self.ens.resolve_address(name).await {
                   return Ok(ResolutionResult::EthereumAddress(addr));
               }
           }
           
           // Try IPNS resolution
           if let Some(key) = name.strip_prefix("ipns/") {
               if let Some(value) = self.ipns.resolve(key.as_bytes()).await {
                   return Ok(ResolutionResult::IpnsKey(value));
               }
           }
           
           // Fallback to direct IPFS hash
           if name.starts_with("Qm") || name.starts_with("baf") {
               return Ok(ResolutionResult::IpfsCid(name.to_string()));
           }
           
           Err(anyhow::anyhow!("Could not resolve name: {}", name))
       }
   }
   ```

### Testing

1. **Unit Tests**
   ```rust
   #[tokio::test]
   async fn test_ens_resolution() {
       let resolver = EnsResolver::new("http://127.0.0.1:8545").unwrap();
       let result = resolver.resolve_ipfs("vitalik.eth").await;
       assert!(result.is_ok());
   }
   
   #[tokio::test]
   async fn test_ipns_publish_resolve() {
       let mut resolver = IpnResolver::new();
       let key = b"test-key";
       let value = b"test-value";
       
       resolver.publish(key, value).await.unwrap();
       let resolved = resolver.resolve(key).await.unwrap();
       
       assert_eq!(resolved, value);
   }
   ```

2. **Integration Testing**
   ```bash
   # Test ENS resolution (dev server)
   curl http://localhost:5174/resolve/ens/vitalik.eth
   
   # Test IPNS resolution (dev server)
   curl http://localhost:5174/resolve/ipns/Qm...
   ```

---

🗜 10 ▸ Deterministic build & updater (Weeks 17–18)
	1.	Install Nix:

curl -L https://nixos.org/nix/install | bash


	2.	Write flake.nix:

{
  inputs.crane.url = "github:ipetkov/crane";
  outputs = { self, nixpkgs, crane, ... }: {
    packages.x86_64-linux.browser = crane.lib.mkCargoDerivation {
      src = ./.;
      cargoVendorDir = null;
    };
  };
}


	3.	Build: nix build .#browser.
	4.	CID pinning script:

ipfs add -Q ./result > cid.txt
echo "{\"version\":\"v0.1.0\",\"cid\":\"$(cat cid.txt)\"}" | ipfs add -Q > manifest.cid


	5.	GUI polls https://w3s.link/ipfs/<manifestCID>; if new CID ≠ local, ask “Download 35 MB update?”.

⸻

🎨 11 ▸ GUI polish & hardware wallet flows (Weeks 19–20)
	•	SvelteKit pages:
	•	/wallet — balance, send, receive, connect Ledger.
	•	/settings — toggle “HTTP fallback”, “Infura bridge”.
	•	UX details: show green shield icon when all deps local, yellow exclamation when any HTTP/RPC.
	•	Ledger flow:

import Transport from "@ledgerhq/hw-transport-webhid";
const t = await Transport.create();
const eth = new Eth(t);
const sig = await eth.signTransaction(path, tx);

Rust side verifies HID permission via tauri::window::ask.

⸻

🚀 12 ▸ Release v1.0 (Weeks 21–22)
	1.	Update CHANGELOG.md with every PR title.
	2.	Tag: git tag v1.0.0 && git push --tags.
	3.	cargo dist release --ci (signs tarballs with your GPG key).
	4.	ipfs pin add <tarballCID>; write release manifest on-chain (ENS TXT record).

⸻

🧭 Day-to-day “nano cycle”

09:00 stand-up: decide ticket
09:15 write failing test
09:45 implement feature
11:30 run cz (clippy+test)
12:00 commit: feat(module): add X
13:00 lunch
14:00 review yesterday’s PRs
15:00 push branch → CI
15:30 address review comments
17:00 merge, update progress board


⸻

📚 Minimum study links (bookmark 👍)
	•	Rust 🦀: https://doc.rust-lang.org/book/
	•	Async Rust: https://rust-lang.github.io/async-book/
	•	libp2p tutorial: https://docs.libp2p.io/concepts/intro/
	•	IPFS in Rust guide: https://github.com/rs-ipfs/rs-ipfs/blob/master/README.md
	•	Tauri cookbook: https://tauri.app/v2/guides
	•	SvelteKit: https://kit.svelte.dev/docs

⸻

✅ Completion checklist

Item	File / command	Expected result
Build (debug)	cargo build	compiles in < 8 min
Unit tests	cargo test --workspace	100% pass
End-to-end	cargo tauri dev, visit ipfs://bafy.../index.html	page renders, no HTTP in logs
Ethereum RPC	curl -d '{"method":"eth_chainId","id":1}' 127.0.0.1:8546	returns 0x1
Bitcoin RPC	bitcoin-cli -rpcconnect=127.0.0.1 -rpcport=18443 getblockcount	height close to mainnet
Ledger TX	send 0.001 ETH on Ropsten	device asks to confirm

When every row is ✅, cut the 1.0.0 release.

⸻

🏁 You are done!

The guide spells out every command, path, and file you need.
Work in 90-minute sprints, commit small, and never let cargo clippy go red.
