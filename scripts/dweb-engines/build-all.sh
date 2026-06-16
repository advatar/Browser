#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/scripts/dweb-engines/build-storage-adapters.sh"
"$ROOT_DIR/scripts/dweb-engines/package-macos.sh"
"$ROOT_DIR/scripts/dweb-engines/smoke.sh"
