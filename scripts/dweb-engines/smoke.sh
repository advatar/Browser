#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

node --test \
  "$ROOT_DIR/services/storage-adapters/src/handlers.test.mjs" \
  "$ROOT_DIR/services/storage-adapters/src/private-overlays.test.mjs"
