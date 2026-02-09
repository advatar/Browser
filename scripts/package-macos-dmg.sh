#!/bin/bash
set -euo pipefail

# Build and export the macOS DMG produced by Tauri bundler.
# Output: dist/decentralized-browser-v<version>-<arch>.dmg

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "error: macOS DMG packaging must run on macOS (OSTYPE=${OSTYPE:-unknown})" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(node -e "const fs=require('fs');const p='crates/gui/tauri.conf.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));process.stdout.write(j.version);")"
mkdir -p dist

echo "Building Tauri DMG (version=${VERSION})..."
(cd crates/gui && cargo tauri build --bundles dmg)

DMG_DIR="target/release/bundle/dmg"
DMG_PATH="$(ls -1 "${DMG_DIR}"/*.dmg 2>/dev/null | head -n 1 || true)"
if [[ -z "${DMG_PATH}" ]]; then
  echo "error: no DMG found in ${DMG_DIR}" >&2
  exit 1
fi

DMG_BASENAME="$(basename "${DMG_PATH}")"
ARCH="$(echo "${DMG_BASENAME}" | sed -E "s/.*_${VERSION}_([A-Za-z0-9_]+)\\.dmg/\\1/")"
if [[ -z "${ARCH}" || "${ARCH}" == "${DMG_BASENAME}" ]]; then
  ARCH="unknown"
fi

OUT_PATH="dist/decentralized-browser-v${VERSION}-${ARCH}.dmg"
cp -f "${DMG_PATH}" "${OUT_PATH}"

echo "Wrote ${OUT_PATH}"
if command -v shasum >/dev/null 2>&1; then
  (cd dist && shasum -a 256 "$(basename "${OUT_PATH}")" > "SHA256SUMS.macos.txt")
  echo "Wrote dist/SHA256SUMS.macos.txt"
fi

