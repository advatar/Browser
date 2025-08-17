# Blockchain Light Clients

This guide explains how to use the embedded Ethereum and Substrate/Polkadot light clients in the browser.

The browser runs light clients locally to remove reliance on centralized RPC endpoints. On launch, light clients initialize in the background and start syncing headers. You can browse IPFS/ENS and send transactions once headers are sufficiently synced.

## What is a light client?
- Verifies block headers and essential proofs locally.
- Downloads a tiny fraction of the chain compared to full nodes.
- Offers better privacy and decentralization than remote RPC.

## Supported networks
- Ethereum-compatible chains (light client for header verification; ENS resolution supported)
- Substrate-based chains (e.g., Polkadot, Kusama, and Substrate dev nodes)

## Basic usage
- Create or import a wallet in the Wallet panel.
- Navigate to decentralized resources (e.g., `ipfs://...`, `ipns://...`, `ens://...`).
- When sending a transaction, the wallet signs locally and the light client broadcasts it via the p2p network.

### ENS resolution (Ethereum)
- Enter an ENS domain like `ens://vitalik.eth` in the address bar.
- The browser resolves the content hash via Ethereum and loads the IPFS content through your configured IPFS gateway.

## Configuration

### Environment variables (optional)
These are primarily for development/testing and will make the browser use external nodes instead of the embedded light clients.

- `SUBSTRATE_WS_URL`: WebSocket URL to a Substrate node (e.g., `ws://localhost:9944`).
- `ETHEREUM_RPC_URL`: HTTP/WS URL to an Ethereum RPC (e.g., `http://localhost:8545`).

When these are set, the browser may use them as a fallback transport for development.

### Home page and gateways
- Default homepage: `about:home` (curated IPFS/ENS links and frequent sites)
- Default IPFS gateway: `https://ipfs.io`
- Default ENS resolver host: `https://eth.limo`

You can change these in Settings → Network and Appearance (if present) or via future configuration options.

## Troubleshooting
- Light client stuck on syncing:
  - Leave the app running for a few minutes to discover peers.
  - Check your network/firewall allows outbound p2p connections.
  - Try restarting the app.
- ENS not resolving:
  - Ensure you have network connectivity.
  - Try navigating directly to `ipfs://` or `ipns://` content.
- Transactions pending for long:
  - Network may be congested; try again or increase fee.

See `docs/TROUBLESHOOTING.md` for more tips.
