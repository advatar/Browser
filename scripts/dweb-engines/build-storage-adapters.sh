#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/versions.env"

PACKAGE_DIR="$ROOT_DIR/$DBROWSER_STORAGE_ADAPTERS_PACKAGE"
BUILD_DIR="$ROOT_DIR/$DBROWSER_DWEB_DIST_DIR/build/$DBROWSER_STORAGE_ADAPTERS_HELPER"
BIN_DIR="$BUILD_DIR/bin"
LIB_DIR="$BUILD_DIR/lib/$DBROWSER_STORAGE_ADAPTERS_HELPER"

test -f "$PACKAGE_DIR/package.json"
test -f "$PACKAGE_DIR/src/server.mjs"

npm --prefix "$PACKAGE_DIR" install

rm -rf "$BUILD_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR"
cp "$PACKAGE_DIR/package.json" "$LIB_DIR/package.json"
cp -R "$PACKAGE_DIR/src" "$LIB_DIR/src"
if [ -d "$PACKAGE_DIR/node_modules" ]; then
  cp -R "$PACKAGE_DIR/node_modules" "$LIB_DIR/node_modules"
fi

cat > "$BIN_DIR/$DBROWSER_STORAGE_ADAPTERS_HELPER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/dweb-storage-adapters" && pwd)"
exec node "$HELPER_DIR/src/server.mjs"
SH
chmod +x "$BIN_DIR/$DBROWSER_STORAGE_ADAPTERS_HELPER"

printf 'Built %s in %s\n' "$DBROWSER_STORAGE_ADAPTERS_HELPER" "$BUILD_DIR"
