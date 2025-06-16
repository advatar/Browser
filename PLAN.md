Below is a microscopic, command-level build manual.
If you hand it to a junior developer who has only a basic grasp of Rust and JavaScript, they can still land a working v 1.0 in ± 6 months.

⸻

🖥 0 ▸ Workstation setup (1 day)

What	Exact commands / clicks
OS packages	Ubuntu 22.04: bash sudo apt update && sudo apt install -y build-essential libssl-dev pkg-config cmake curl git tmux zsh unzip libudev-dev libdbus-1-dev libgtk-3-dev libwebkit2gtk-4.0-dev
Rust toolchain	```bash curl https://sh.rustup.rs -sSf
Node + pnpm	```bash curl -fsSL https://deb.nodesource.com/setup_20.x
Git basics	git config --global user.name "Your Name"git config --global user.email you@example.com
Editor	Install VS Code → Settings → enable “Rust Analyzer”, “Prettier”, “Svelte for VS Code”.
Shell profile	Add to ~/.zshrc:alias cz='cargo watch -x check -x test'alias ct='cargo test -- --nocapture'Reload: source ~/.zshrc
Success check	rustc --version && cargo --version && node -v && pnpm -v show versions without error.


⸻

📂 1 ▸ Bootstrap monorepo (2 days)
	1.	Directory layout

mkdir -p ~/code/browser
cd ~/code/browser
git init -b main
echo "# Decentralised Browser" > README.md


	2.	Cargo workspace

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
mkdir -p crates/{p2p,ipfs,eth-light,btc-light,walletd,gui}/src
for c in p2p ipfs eth-light btc-light walletd gui; do
  cat > crates/$c/Cargo.toml <<EOF
[package]
name = "$c"
version = "0.0.0"
edition = "2021"

[dependencies]
EOF
  echo 'fn main() { println!("hello"); }' > crates/$c/src/main.rs
done


	3.	Continuous Integration
Create .github/workflows/ci.yml:

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


	4.	Pre-commit hooks

pnpm dlx husky-init && pnpm install
npx husky set .husky/pre-commit "cargo fmt && cargo clippy --workspace -- -D warnings"
git add .
git commit -m "chore: bootstrap workspace"



⸻

🌐 2 ▸ libp2p transport skeleton (Week 2)

Day	Steps	Details / pitfalls
Mon	Create p2p library	In crates/p2p/Cargo.toml add:toml [dependencies] libp2p = { version = "0.55", features = ["tcp","noise","yamux","identify"] } tracing = "0.1" async-std = { version = "1.12", features=["attributes"] }
	Basic swarm example	src/lib.rs:rust use libp2p::{identity, noise, swarm::SwarmBuilder, tcp::TokioTcpTransport, yamux, PeerId}; pub fn new() -> anyhow::Result<(PeerId, libp2p::Swarm<impl Send + 'static>)> { let key = identity::Keypair::generate_ed25519(); let peer_id = key.public().to_peer_id(); let trans = TokioTcpTransport::new(libp2p::tcp::Config::default().nodelay(true)); let noise_keys = noise::Keypair::<noise::X25519Spec>::new().into_authentic(&key)?; let muxer = yamux::YamuxConfig::default(); let transport = trans.upgrade(libp2p::core::upgrade::Version::V1).authenticate(noise_keys).multiplex(muxer).boxed(); let behaviour = libp2p::ping::Behaviour::new(libp2p::ping::Config::new()); let swarm = SwarmBuilder::with_executor(transport, behaviour, peer_id, async_std::task::spawn).build(); Ok((peer_id, swarm)) }
	Compile + test	cargo test -p p2p (no tests yet, compilation confirms config).
Tue	Add CLI bin	In crates/p2p/Cargo.toml add [[bin]] name = "p2pd" path = "src/bin/main.rs".main.rs starts the swarm, listens on /ip4/0.0.0.0/tcp/0, prints the multiaddr.
	Local discovery	Open two terminals, run p2pd. Manually swarm.dial(addr?) (temporarily hard-code) → ping round-trip logs.
Wed	Wrap Swarm in tokio service	Add tokio feature to p2p; replace async-std with tokio (libp2p supports both).
Thu	Metrics	cargo add prometheus --features process ; expose metrics::gather() via tiny HTTP on 127.0.0.1:9870 (use hyper).
Fri	Unit test harness	In tests/ spawn two swarms on different ephemerals, assert ping RTT < 1 s.

Commit messages
	•	feat(p2p): minimal libp2p swarm
	•	feat(p2p): prometheus metrics exporter

⸻

📦 3 ▸ Embedded IPFS node (Weeks 3–5)

Week 3 — blockstore & CID maths
	1.	cargo add cid multihash sled
	2.	Implement blockstore::SledStore { db: sled::Db }.
	3.	Functions:

pub fn put(&self, data: &[u8]) -> Cid
pub fn get(&self, cid: &Cid) -> Option<Vec<u8>>


	4.	Unit test: generate random 1 KB, store, retrieve, compare.

Week 4 — Bitswap plumbing
	1.	cargo add rust-ipfs --git https://github.com/rs-ipfs/rust-ipfs
	2.	Inside ipfs/src/lib.rs create Node::new(sw: Swarm) that mounts rust-ipfs Behaviour onto existing p2p Swarm using NetworkBehaviour derive.
	3.	Pitfall: both libs export NetworkBehaviour; use pub use renames + #[behaviour(out_event = "Event")].

Week 5 — CLI ipfs-cat
	1.	Add bin target in ipfs.
	2.	Parse first CLI arg as CID (cid::Cid::try_from).
	3.	Call node.get_block_stream(cid) → write to stdout with tokio::io::stdout().write_all(...).
	4.	Manual test:

cargo run -p ipfs --bin ipfs-cat QmYwAPJzv5CZsnAzt... > logo.png
eog logo.png



⸻

⛓ 4 ▸ Ethereum light client (Weeks 6–8)

Week 6 — Trin sub-crate

cargo add trin --git https://github.com/ethereumportal/trin.git#v0.5.0

Warning: Trin pulls 80+ crates; first build ~10 min.
	•	eth-light/src/lib.rs:

pub async fn start(config: &Config) -> anyhow::Result<JoinHandle<()>> {
    let trin_config = trin::config::TrinConfig::from_cli();
    let portal = trin::portalnet::PortalnetConfig::from(trin_config.clone());
    let handle = tokio::spawn(async move {
        trin::run(trin_config, portal).await.unwrap();
    });
    Ok(handle)
}



Week 7 — JSON-RPC shim
	1.	cargo add jsonrpsee
	2.	Expose HTTP port 8546:

let server = HttpServerBuilder::default().build("127.0.0.1:8546").await?;
server.register_method("eth_chainId", |params, _| async {
    Ok(format!("0x{:x}", CHAIN_ID))
})?;


	3.	Implement eth_getBlockByNumber by querying Trin’s header database (trin::u256id::HistorySqlite).
	4.	Write cURL integration test in tests/eth_rpc.rs.

Week 8 — Proof helper
	•	cargo add reth-primitives reth-rlp
	•	Implement verify_account_proof(); create Golden-file test that verifies Vitalik’s balance at block #1.

⸻

🪙 5 ▸ Bitcoin light client (Weeks 9–10)
	1.	cargo add neutrino (use BDK fork).
	2.	btc-light/src/lib.rs:

pub async fn sync(net: Network) -> anyhow::Result<NodeHandle> {
    let conf = neutrino::Config::default();
    let (node, mut events) = neutrino::Node::new(conf).await?;
    tokio::spawn(async move { while let Some(e) = events.recv().await { println!("{e:?}"); }});
    node.start().await?;
    Ok(node)
}


	3.	Mini-RPC: depend on jsonrpsee; methods getblockheader, getblock.

⸻

🔐 6 ▸ Wallet subsystem (Weeks 11–12)
	1.	cargo add bip32 slip10 coins-bip39 directories-next
	2.	Local keystore located at
~/.local/share/browser/keys/keystore.json (AES-GCM, password from env WALLET_PW).
	3.	Use hidapi for Ledger/Trezor (U2F):

cargo add hidapi --features linux-static-hidraw


	4.	Expose IPC provider:
	•	Unix: /tmp/browser-wallet.ipc
	•	Windows: Named pipe \\.\pipe\browser-wallet
	5.	JSON schema exactly matches EIP-1193.

⸻

🖼 7 ▸ Desktop GUI with Tauri (Weeks 13–14)
	1.	

cargo install tauri-cli@2
pnpm create tauri-app@latest gui


	2.	In front-end choose SvelteKit template.
	3.	IPC command example:

import { invoke } from "@tauri-apps/api/core";
export async function getPeerId() {
  return await invoke<string>("peer_id");
}

Register in Rust:

#[tauri::command]
fn peer_id(state: tauri::State<'_, P2pState>) -> String {
    state.0.peer_id.to_string()
}


	4.	Start dev loop: pnpm dev in web directory + cargo tauri dev.

⸻

📡 8 ▸ Custom ipfs:// protocol handler (Week 15)

tauri::Builder::default()
    .register_uri_scheme_protocol("ipfs", move |_app, request| {
        let url = Url::parse(request.uri()).unwrap(); // ipfs://<CID>/path
        let cid = url.host_str().unwrap();
        let path = url.path();
        let bytes = ipfs::cat_path(cid, path).await?;
        tauri::http::ResponseBuilder::new()
            .header("Content-Type", mime_guess::from_path(path).first_or_octet_stream().as_ref())
            .status(200)
            .body(bytes)
    })

Use streaming body to avoid loading entire 5 MB video in RAM.

⸻

🔖 9 ▸ ENS + IPNS resolution (Week 16)
	1.	ENS:

let provider = ethers::providers::Provider::try_from("http://127.0.0.1:8546")?;
let ens = ethers::ens::Ens::new(provider.clone());
let cid_txt = ens.text("bravo.eth", "ipfs").await?;


	2.	IPNS: libp2p::kad::record::store::MemoryStore + libp2p::kad::Behaviour.
Key: Key::new(&hash)
Record: signed protobuf‐encoded value.

⸻

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
