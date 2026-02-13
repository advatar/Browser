#!/bin/bash
set -euo pipefail

# Build and export the macOS DMG produced by Tauri bundler.
# Output: dist/decentralized-browser-v<version>-<arch>.dmg
#
# Production checks:
# - Set PROD_RELEASE=1 to require signature + notarization validation.
# - Or set STRICT_SIGNING=1 / STRICT_NOTARIZATION=1 individually.

if [[ "${OSTYPE:-}" != darwin* ]]; then
  echo "error: macOS DMG packaging must run on macOS (OSTYPE=${OSTYPE:-unknown})" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(node -e "const fs=require('fs');const p='crates/gui/tauri.conf.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));process.stdout.write(j.version);")"
mkdir -p dist

STRICT_SIGNING="${STRICT_SIGNING:-0}"
STRICT_NOTARIZATION="${STRICT_NOTARIZATION:-0}"
if [[ "${PROD_RELEASE:-0}" == "1" ]]; then
  STRICT_SIGNING=1
  STRICT_NOTARIZATION=1
fi

echo "Building Tauri DMG (version=${VERSION})..."
(cd crates/gui && cargo tauri build --bundles dmg)

DMG_DIR="target/release/bundle/dmg"
APP_DIR="target/release/bundle/macos"
DMG_PATH="$(ls -1 "${DMG_DIR}"/*.dmg 2>/dev/null | head -n 1 || true)"
APP_PATH="$(ls -1d "${APP_DIR}"/*.app 2>/dev/null | head -n 1 || true)"

if [[ -z "${DMG_PATH}" ]]; then
  echo "error: no DMG found in ${DMG_DIR}" >&2
  exit 1
fi

if [[ -z "${APP_PATH}" ]]; then
  echo "error: no .app bundle found in ${APP_DIR}" >&2
  exit 1
fi

if [[ "${STRICT_SIGNING}" == "1" ]]; then
  if ! command -v codesign >/dev/null 2>&1; then
    echo "error: codesign is required when STRICT_SIGNING=1" >&2
    exit 1
  fi
  if ! command -v spctl >/dev/null 2>&1; then
    echo "error: spctl is required when STRICT_SIGNING=1" >&2
    exit 1
  fi

  echo "Verifying app signature..."
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
  spctl --assess --type execute --verbose=4 "${APP_PATH}"
fi

DMG_BASENAME="$(basename "${DMG_PATH}")"
ARCH="$(echo "${DMG_BASENAME}" | sed -E "s/.*_${VERSION}_([A-Za-z0-9_]+)\.dmg/\1/")"
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

if [[ "${STRICT_NOTARIZATION}" == "1" ]]; then
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun is required when STRICT_NOTARIZATION=1" >&2
    exit 1
  fi

  echo "Validating DMG notarization ticket..."
  xcrun stapler validate "${OUT_PATH}"
fi
