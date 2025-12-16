#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export ADVATAR_ETH_RPC=${ADVATAR_ETH_RPC:-http://localhost:8545}

echo "Starting local infrastructure (Anvil) and launching the app..."
cd "$ROOT"

# Start devnet
docker compose up -d anvil

echo "Anvil running at $ADVATAR_ETH_RPC"
echo "Building and launching the GUI app..."
cargo run -p gui
