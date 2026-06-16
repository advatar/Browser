#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/versions.env"

BUILD_DIR="$ROOT_DIR/$DBROWSER_DWEB_DIST_DIR/build/$DBROWSER_STORAGE_ADAPTERS_HELPER"
PACKAGE_DIR="$ROOT_DIR/$DBROWSER_DWEB_DIST_DIR/macos"
BIN_DIR="$PACKAGE_DIR/Contents/Library/DWebEngines/bin"
RESOURCE_DIR="$PACKAGE_DIR/Contents/Resources/DWebEngines"

test -x "$BUILD_DIR/bin/$DBROWSER_STORAGE_ADAPTERS_HELPER"

rm -rf "$PACKAGE_DIR"
mkdir -p "$BIN_DIR" "$RESOURCE_DIR"
cp -R "$BUILD_DIR/bin/$DBROWSER_STORAGE_ADAPTERS_HELPER" "$BIN_DIR/"
cp -R "$BUILD_DIR/lib" "$PACKAGE_DIR/Contents/Library/DWebEngines/lib"

cat > "$RESOURCE_DIR/manifest.json" <<JSON
{
  "version": "$DBROWSER_DWEB_ENGINE_CONTRACT_VERSION",
  "helper": "$DBROWSER_STORAGE_ADAPTERS_HELPER",
  "portRange": "$DBROWSER_STORAGE_ADAPTERS_PORT_RANGE",
  "license": "$DBROWSER_STORAGE_ADAPTERS_LICENSE",
  "routes": [
    "/dweb/filecoin/native",
    "/dweb/walrus/native",
    "/dweb/iroh/native",
    "/dweb/hypercore/native",
    "/dweb/sia/native",
    "/dweb/storj/native",
    "/dweb/tahoe-lafs/native",
    "/dweb/autonomi/native",
    "/dweb/bittorrent/native",
    "/dweb/ceramic/native",
    "/dweb/orbitdb/native",
    "/dweb/radicle/native"
  ]
}
JSON

printf 'Packaged macOS DWeb engines in %s\n' "$PACKAGE_DIR"
