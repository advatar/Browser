Below is a command-level, junior-friendly build manual for the v 1.1 cycle.
The scope is everything promised after 1.0:
	•	Privacy transports – Tor + Dandelion++ for transaction relay
	•	ZK-verified historical state – SNARK proofs for EVM headers & account/storage proofs
	•	Community extension store – signed WASM/JS add-ons distributed over IPFS
	•	Misc polish (automatic proof-cache GC, UX flags, docs)

The schedule assumes you start the day after 1.0 ships and you are still the lone developer.
Total: 8 calendar weeks ≈ 30 developer-days.

⸻

🛣  High-level road-map

Phase	Goal	Duration	Main artifact
A	ZK tool-chain bootstrap	3 days	zk/ workspace builds (no proofs yet)
B	Privacy transports (Tor & Dandelion++)	1 week	peer-to-peer traffic runs through Tor or Dandelion hops
C	ZK header verifier (EVM)	2 weeks	eth-zk crate exposes verify_header_snark()
D	ZK account/storage proof verifier	1 week	eth-zk exposes verify_account_snark()
E	Extension store (backend on IPFS + UI)	1 week	/extensions tab installs, enables, updates add-ons
F	Release plumbing, docs & QA	1 week	v1.1.0 tag & signed CID


⸻

A ▸ ZK tool-chain bootstrap (Days 1–3)

Day	Task	Exact commands / notes
1	OS deps	bash sudo apt install -y clang llvm libgmp-dev (needed by arkworks & Halo2)
	Workspace skeleton	bash mkdir zk && cd zk && cargo new halo2-verifier --lib
	Common crates	In zk/Cargo.toml add: ark-ff = "0.4"ark-ec = "0.4"halo2_proofs = { git = "https://github.com/halo2-rust/halo2.git", package="halo2_proofs" }
2	Build check	bash cargo test -p halo2-verifier (compiles empty crate)
3	FFI glue (optional WASM for future extensions)	bash cargo add wasm-bindgen --features wasm-bindgen Expose stub pub fn verify(bytes: &[u8]) -> bool.

Commit: chore(zk): scaffold halo2 verifier crate.

⸻

B ▸ Privacy transports (Week 1)

B-1  Tor overlay (Days 4–5)

Step	Detail
1	cargo add arti-client (Mozilla’s async Tor stack)
2	In crates/p2p/src/tor.rs create pub async fn tcp_over_tor(addr: &str) -> io::Result<TcpStream> that wraps arti_client::TorClient::bootstrap()?; client.connect(addr).await?.
3	Behind feature flag tor, replace the default TokioTcpTransport in libp2p builder with one that dials through tcp_over_tor when the user toggles “Tor mode”.
4	GUI: Settings → checkbox “Route P2P traffic through Tor (requires restart)”

Manual test

RUST_LOG=debug cargo run -p p2p --features tor
# expect bootstrap to .onion guards, peer handshake logs show ".onion" addr

B-2  Dandelion++ relay for TXs (Days 6–7)

Step	Detail
1	cargo add dandelion (crate implementing BIP-156-like stem/fluff)
2	In walletd intercept sendTransaction; if Dandelion mode is on, call dandelion::stem(tx_bytes, &p2p_swarm).await.
3	After random epoch (~10 s) promote to “fluff” by broadcasting over normal gossipsub.
4	Setting lives next to Tor toggle.  Yellow padlock icon in tab header turns green only when both Tor and Dandelion are enabled (full privacy).

Commit series
	•	feat(p2p): optional tor transport
	•	feat(wallet): dandelion++ tx relay

⸻

C ▸ ZK header verifier (Weeks 2–3)

C-1  Protocol choice & data feed (Day 8)
	•	Use Succinct Portal LC ➜ delivers weekly SNARKs of Ethereum headers.
	•	Each proof bundle = { "header_root": <poseidon>, "prev_hash": <H>, "proof": <bytes> } hosted at ipfs://<cid>.

C-2  New crate layout (Day 9)

cargo new crates/eth-zk --lib

crates/eth-zk/Cargo.toml:

[dependencies]
halo2_proofs = { path = "../../zk/halo2-verifier" }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha3 = "0.10"

C-3  Verifier circuit glue (Days 10–12)
	1.	Download verification key once:

const VK_CID: &str = "bafy...vk";
lazy_static! {
    static ref VK: PlonkVerifierKey<G1Affine> = {
        let bytes = ipfs::cat(VK_CID).await.unwrap();
        PlonkVerifierKey::read(&mut &bytes[..]).unwrap()
    };
}


	2.	Implement

pub fn verify_header_snark(proof_blob: &[u8], expected_root: H256) -> bool

which:
	•	parses Proof<Groth16>,
	•	feeds into halo2_proofs::verify_proof,
	•	checks public input equals expected_root.

	3.	Unit test uses small devnet proof fixture:

cargo test -p eth-zk -- --nocapture



C-4  Wiring into eth-light (Days 13–14)
	•	Extend eth-light header sync: after downloading header H_n, fetch proof bundle for the epoch (e.g., every 8192 blocks) via IPFS, call verify_header_snark().
	•	Mark local DB row headers.is_verified = true.

C-5  GUI indicators (Day 15)
	•	Chain badge:
	•	grey = unverified,
	•	green = latest header verified.
	•	Tooltip shows last verified block + epoch root.

Commits
	•	feat(eth-zk): header snark verifier
	•	feat(eth-light): mark verified epochs
	•	feat(gui): header verification badge

⸻

D ▸ ZK account/storage proof verifier (Week 4)

Day	Task	Commands / code sketch
16	SNARK input format: Succinct publishes proof.json with state_root, addr, storage_key, value.	
17	eth-zk/src/account.rs add verify_account_snark(proof: &[u8], expected_value: H256) -> bool.  Re-use same VK constant (different circuit id).	
18	Wallet: before signing any transaction with from: myAddr, call verify_account_snark() for nonce & balance.  Abort signing if fails.	
19	Opt-in: default off (proof fetch ~200 kB).  Settings → “Self-verify state before signing”.	
20	Integration test: spin up anvil --fork + generate local proof with Succinct CLI (documented in docs/zk.md).	

Commits
	•	feat(eth-zk): account proof verification
	•	feat(wallet): pre-sign ZK check

⸻

E ▸ Community extension store (Week 5)

E-1  Manifest & signing (Days 21–22)

Item	Spec
File	extension.json (IPFS)
Fields	name, version, author_pubkey, sig, wasm_cid, permissions:[cap...]
Signing	Ed25519; CLI browserctl ext sign ./dist.wasm --key ~/.ssh/ed25519_ext writes .sig & embeds in manifest

CLI implementation:

cargo new crates/ext-cli --bin
cargo add ed25519-dalek base64

E-2  Store index (Day 23)
	•	Directory ipfs://bafy...store/index.json → array of manifest CIDs.
	•	A GitHub Action in separate store-repo updates the list on PR merge.

E-3  GUI (Days 24–25)
	•	New /extensions tab.
	•	Fetch index.json, list cards; on “Install” → pin wasm_cid, validate sig, move file to ~/.local/share/browser/extensions/<name>/<ver>/main.wasm.
	•	Permissions modal lists capabilities; user must check “I accept”.

E-4  Runtime load (Day 26)
	•	At browser boot: iterate dirs, wasmtime::Engine::new().module(wasm), provide IPC imports matching requested caps.
	•	Sandboxed extensions run in separate async tasks; killed on version mismatch.

Commits
	•	feat(ext): signing CLI
	•	feat(gui): extension store
	•	feat(core): wasm extension loader

⸻

F ▸ Release, docs, QA (Week 6)

Day	Checklist item
27	Proof-cache GC – new background job deletes proofs older than 3 epochs (~/.local/share/browser/proofs).
28	Security scan – cargo audit, cargo deny, run OWASP-ZAP on custom protocol handler.
29	Docs – update docs/zk.md, docs/privacy.md, screenshot new Settings & Extension tabs.
30	Tag & publish: git tag v1.1.0 && git push --tags; cargo dist release; pin binaries to IPFS; update ENS text record version=v1.1.0;cid=<CID>


⸻

📋  Daily micro-cycle (unchanged)

09:00 choose ticket  ► write failing test
09:45 pass test     ► run clippy
11:30 commit        ► lunch
14:00 code review   ► coding
17:00 merge & push


⸻

🗂  File / command acceptance checklist

Item	Command / path	Expectation
Tor transport	BROWSER_TOR=1 cargo run -p p2p	peer logs show .onion
Dandelion++	send 2 TXs, second within 10 s	first stem, second fluff
Header proof	browserctl zk verify-header latest	prints “✔ verified”
Account proof	attempt to sign with wrong state	wallet modal shows “ZK mismatch, abort”
Extension install	/extensions → click Install	card badge turns Enabled
GC	du -sh ~/.local/share/browser/proofs	size ≤ 150 MB after GC run
Release	ipfs cat <manifestCID>	shows "version":"v1.1.0"

When every row is ✅, ship v1.1.0.

⸻

🎉  You are set!

The plan retains the same granularity as the v 1.0 guide—down to crate names, flags, and UI checkboxes—while layering privacy and ZK safety on top.
Stay disciplined with tests + small commits and you’ll land v 1.1 in six weeks of focused, junior-friendly work.
