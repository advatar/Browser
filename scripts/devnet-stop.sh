#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Stopping local Anvil devnet..."
cd "$ROOT"
docker compose stop anvil
echo "Devnet stopped."

