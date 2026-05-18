# Native Protocol Engine Bundling Plan

Issue: [#133](https://github.com/advatar/Browser/issues/133)

## Requirement

dBrowser users must not be expected to install protocol daemons, runtimes, CLIs, Node packages, Python packages, wallets, or storage services before protocol URIs work. The app should bundle the needed engines wherever platform rules allow it, start and supervise them itself, and expose one consistent Swift resolver surface to the rest of the browser.

The only acceptable user-provided prerequisites are secrets or economic resources that cannot be bundled:

- Storage credentials, access grants, read/write caps, API tokens, peer identities, and private keys.
- Chain funds, storage deposits, or payment approvals.
- Explicit permission for a protocol to use network, disk, wallet, or background execution.
- Optional enterprise/self-hosted endpoints when the user chooses not to run the bundled local engine.

## Platform Boundary

### macOS

Bundle aggressively. The macOS app can ship signed helper executables and native libraries inside the app bundle, then supervise them as child processes bound to loopback or app-private IPC. This is the correct default for daemon-first protocols such as renterd, Tahoe-LAFS, Radicle, Ceramic, OrbitDB/IPFS, Hypercore, and torrent engines.

Target layout:

- `Contents/Library/DWebEngines/bin/` for signed helper executables.
- `Contents/Library/DWebEngines/lib/` for native libraries and FFI shims.
- `Contents/Resources/DWebEngines/manifest.json` for engine versions, checksums, ports, capabilities, and licenses.
- App-private storage under `Application Support/dBrowser/DWebEngines/`.
- Per-engine process supervision owned by Swift, with health checks and automatic restart for recoverable failures.

### iOS and iPadOS

Bundle only code that ships as part of the signed app. Apple's review rules require apps to be self-contained and prohibit downloading, installing, or executing code that changes app functionality after review. Therefore iOS cannot rely on installing arbitrary helper daemons after the app is on a device.

The iOS path is:

- Pure Swift implementations where feasible.
- Rust/C/C++/Go code built ahead of time as signed Swift-callable `xcframework`s where feasible.
- WebKit/JavaScriptCore-only support for protocol logic that can run safely as bundled source and does not require Node native modules or daemon privileges.
- App-managed remote fallback only when a native mobile stack is not realistically portable yet. This must be explicit and not presented as native support.

## Architecture

### One Swift Contract

All protocols should conform to a single Swift-side resolver contract:

- Parse and normalize protocol URIs.
- Decide whether the current platform has an in-process engine, managed helper, or configured remote endpoint.
- Start or attach to a bundled engine if needed.
- Stream content bytes back to the browser runtime.
- Return typed verification metadata, trust boundaries, and exact missing credential requirements.
- Never leak secrets into logs, URLs, issue telemetry, or A2UI messages.

The current local adapter service remains useful as the compatibility shell. It should evolve from "proxy to a user-installed backend" into "proxy to bundled engine or native library".

### Engine Manager

Add a Swift `DWebEngineManager` responsible for:

- Reading the bundled engine manifest.
- Checking platform compatibility and code signature expectations.
- Allocating app-private ports or IPC endpoints.
- Starting, stopping, and health-checking helpers.
- Passing credentials through Keychain-backed handles instead of environment dumps where possible.
- Recording per-engine status for diagnostics and tests.
- Enforcing disk quotas, cache eviction, and network permission policy.

### Reproducible Build Scripts

Every bundled engine must be reproducible from a clean checkout:

- `scripts/dweb-engines/versions.env` pins upstream versions, git SHAs, checksums, and license metadata.
- `scripts/dweb-engines/bootstrap-macos.sh` installs build prerequisites through Homebrew or official installers.
- `scripts/dweb-engines/bootstrap-ios.sh` installs cross-compilation toolchains and Rust/Go/C++ targets.
- `scripts/dweb-engines/build-all.sh` builds all bundleable engines.
- `scripts/dweb-engines/build-<engine>.sh` builds one engine.
- `scripts/dweb-engines/package-macos.sh` creates signed helper payloads.
- `scripts/dweb-engines/package-xcframeworks.sh` creates Swift-callable framework artifacts.
- `scripts/dweb-engines/smoke.sh` runs protocol fixture retrievals through the same adapter contract used by the app.

The scripts must document every installed tool and must fail when versions drift from `versions.env`.

## Bundling Matrix

| Protocol | Default macOS bundle | Default iOS bundle | Native Swift target | User-provided data still required |
| --- | --- | --- | --- | --- |
| Filecoin | Bundle Lassie-compatible helper first; add CAR/CID verification in Swift. | Ship CAR/CID/IPLD verifier in Swift; investigate Lassie Go library as an `xcframework`. | Swift verifier and retrieval facade; network retrieval likely Go-backed first. | None for public retrieval; optional paid retrieval credentials later. |
| Walrus | Swift HTTP client plus optional local aggregator helper. | Swift HTTP client and verifier. | High. Walrus exposes HTTP aggregator/publisher flows and verification can be Swift-owned. | Wallet/payment approval for writes. |
| Iroh | Rust `iroh`/`iroh-blobs` helper or Rust FFI library. | Rust `xcframework` via UniFFI if QUIC/networking behavior is acceptable on device. | Medium after FFI; pure Swift is not the first move. | Peer identity and optional relay/bootstrap policy. |
| Hypercore/Hyperdrive | Bundle Node/Pear helper with Hypercore storage under app support. | Not daemon-native initially; research bundled JSCore viability, otherwise remote/helper fallback. | Low short-term; pure Swift port is a separate project. | Write keys for private feeds. |
| Sia | Bundle `renterd` helper on macOS. | Use remote renterd or future Go `xcframework` only if size/network behavior is acceptable. | Low for full renter; Swift HTTP client for bundled/remote renterd. | Wallet seed, renterd password, Siacoin funding. |
| Storj | Bundle `libuplink` through Go/C bindings or use hosted gateway mode. | Bundle `libuplink` as an `xcframework` if buildable; otherwise gateway mode. | Medium for wrapper; pure Swift network stack is not first. | Access grant, passphrase, project credentials. |
| Tahoe-LAFS | Bundle Python-based Tahoe node/helper and expose WebAPI locally. | Remote gateway fallback unless a viable embedded Python/static rewrite exists. | Low for full node; Swift WebAPI client only. | Grid introducer/config and read/write caps. |
| Autonomi | Bundle Rust Autonomi client via helper or UniFFI library. | Rust `xcframework` target if upstream builds cleanly for iOS. | Medium after FFI. | Wallet, keys, payment approval for writes. |
| BitTorrent/WebTorrent | Bundle `libtorrent` helper/library for BitTorrent; bundle WebTorrent/Node path only for WebRTC mode. | Prefer `libtorrent` `xcframework`; WebTorrent limited by WebRTC/browser peer behavior. | Medium for wrapper; pure Swift torrent engine is not first. | User consent and legal/content policy controls. |
| Ceramic | Bundle `ceramic-one` helper on macOS; Swift HTTP client to it. | Remote Ceramic node or future Rust/HTTP client if embeddable. | Medium for client, low for full node now. | DID keys and stream write permissions. |
| OrbitDB/IPFS | Bundle Helia/IPFS/libp2p plus OrbitDB JS helper on macOS. | Not full-native initially; investigate bundled JSCore but assume remote/helper fallback. | Low short-term. | Database write keys/identity. |
| Radicle | Bundle `radicle-node` and `radicle-httpd` helper. | Read-only remote/seed access first; Rust FFI later. | Medium for Rust wrapper, low for pure Swift. | Node identity and repo seeding policy. |

## Implementation Phases

### Phase 0: Manifest and Contract

- Add `DWebEngineManifest` and `DWebEngineManager` models in Swift.
- Extend the existing adapter configuration with engine capability states: `inProcess`, `managedHelper`, `remoteFallback`, `missingCredential`, and `unsupportedOnPlatform`.
- Preserve the existing protocol URI semantics and localhost adapter routes so tests and UI behavior remain stable.

### Phase 1: Bundle-First Mac Helpers

- Add reproducible scripts for macOS helpers first because they cover the largest gap.
- Start with helpers that already expose HTTP contracts:
  - Filecoin/Lassie.
  - Sia/renterd.
  - Tahoe-LAFS WebAPI.
  - Radicle node plus HTTP daemon.
  - Ceramic node.
- Update the local `services/storage-adapters` handlers so they prefer app-managed helper endpoints over environment-provided backends.

### Phase 2: Swift-Native HTTP and Verification

- Implement pure Swift clients for protocols where the protocol boundary is already HTTP or content-addressed bytes:
  - Walrus aggregator/publisher reads.
  - Tahoe WebAPI reads when a bundled or remote node exists.
  - Sia renterd API reads when a bundled or remote renter exists.
  - Ceramic HTTP reads when a bundled or remote node exists.
  - Radicle HTTP read API when a bundled or remote seed exists.
- Add CID/CAR verification for Filecoin/IPLD retrievals so the app can verify helper output instead of blindly trusting it.

### Phase 3: Native Libraries for Mobile

- Build Rust/C/C++/Go engines as `xcframework`s:
  - Iroh and Autonomi through Rust plus UniFFI/C ABI.
  - Storj `libuplink` through Go/C bindings.
  - BitTorrent through `libtorrent`.
  - Filecoin retrieval libraries if Lassie can be embedded cleanly.
- Add Swift wrappers with streaming APIs and cancellation.
- Keep helper-process implementations on macOS for the same engines when that is simpler or more observable.

### Phase 4: JS/Daemon-First Protocols

- Hypercore/Hyperdrive, OrbitDB/IPFS, Ceramic, and WebTorrent get bundled macOS JS/helper engines first.
- iOS support is read-only or remote-backed until a signed in-process implementation exists.
- Do not call these "native iOS stacks" until they run without a remote node or downloaded executable code.

### Phase 5: Hardening

- Add fixture-based smoke tests for every protocol URI.
- Add failure tests for missing credentials, missing funds, unsupported platform, helper crash, malformed URI, and verification mismatch.
- Add privacy tests proving secrets are redacted from logs, adapter metadata, and UI explanations.
- Add update and rollback tests for engine manifest migrations.

## Definition of Done

- A fresh macOS checkout can run one script to build or fetch pinned helper engines, package them, and run smoke retrievals.
- The macOS app can retrieve supported protocol URI content without user-installed prerequisites.
- The iOS app ships all native executable code inside the signed app bundle and clearly reports platform-limited protocols.
- Every protocol either retrieves content through a bundled engine/native library or returns a precise missing secret, funding, or platform limitation.
- Documentation lists exact upstream versions, build commands, licenses, and bundle size impact.

## Source Notes

- [Filecoin retrieval docs](https://docs.filecoin.io/basics/how-retrieval-works/basic-retrieval) document Lassie as a retrieval client with CLI and HTTP daemon modes for CAR retrievals.
- [Walrus core concepts](https://docs.wal.app/docs/system-overview/core-concepts) document optional HTTP aggregators/publishers and direct storage-node reconstruction.
- [Iroh blobs docs](https://docs.iroh.computer/protocols/blobs) document Rust `iroh-blobs` usage for content-addressed blob transfer.
- [Storj SDK docs](https://storj.dev/dcs/api/sdk) document `libuplink` as a Go developer library and note community Swift bindings.
- [Tahoe-LAFS WebAPI docs](https://tahoe-lafs-docs-ng.readthedocs.io/en/latest/frontends/webapi.html) document its REST WebAPI and local node HTTP paths.
- [Autonomi client docs](https://docs.autonomi.com/developers/api-reference/autonomi-client) document Rust, Python, and Node.js client APIs.
- [Ceramic installation docs](https://developers.ceramic.network/docs/protocol/ceramic-one/usage/installation) document `ceramic-one` HTTP client packages.
- [OrbitDB API docs](https://api.orbitdb.org/) document its JavaScript/IPFS/Libp2p dependency model.
- [WebTorrent API docs](https://webtorrent.io/docs) document JavaScript browser/node implementations and WebRTC browser constraints.
- [Radicle docs](https://radicle.dev/) and the [Radicle seeder guide](https://radicle.dev/guides/seeder) document that the stack is backed by `radicle-node` and `radicle-httpd`.
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require apps to be self-contained and prohibit downloading/installing/executing code that changes app functionality.
