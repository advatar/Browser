#!/bin/bash
set -euo pipefail

# Backwards-compatible entrypoint.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package-macos-dmg.sh"

