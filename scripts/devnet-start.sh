#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Starting local Anvil devnet via docker compose..."
cd "$ROOT"
docker compose up -d anvil
echo "Local devnet is running on http://localhost:8545"

