#!/bin/bash
set -e

# Build script for generating installer packages
# This script builds the Decentralized Browser for all supported platforms

echo "🚀 Building Decentralized Browser Installers..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf dist/*.dmg dist/*.msi dist/*.deb dist/*.rpm dist/*.AppImage dist/*.exe dist/*.app.tar.gz

# Build for current platform
echo "🔨 Building for current platform..."
cd crates/gui
cargo tauri build

# Copy built artifacts to dist folder
echo "📦 Copying artifacts to dist folder..."
mkdir -p ../../dist

# Find and copy Tauri build outputs
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if [ -f "src-tauri/target/release/bundle/dmg/*.dmg" ]; then
        cp src-tauri/target/release/bundle/dmg/*.dmg ../../dist/
    fi
    if [ -f "src-tauri/target/release/bundle/macos/*.app" ]; then
        tar -czf ../../dist/decentralized-browser-v0.1.0.app.tar.gz -C src-tauri/target/release/bundle/macos/ *.app
    fi
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    # Windows
    if [ -f "src-tauri/target/release/bundle/msi/*.msi" ]; then
        cp src-tauri/target/release/bundle/msi/*.msi ../../dist/
    fi
    if [ -f "src-tauri/target/release/*.exe" ]; then
        cp src-tauri/target/release/*.exe ../../dist/decentralized-browser-v0.1.0.exe
    fi
else
    # Linux
    if [ -f "src-tauri/target/release/bundle/deb/*.deb" ]; then
        cp src-tauri/target/release/bundle/deb/*.deb ../../dist/
    fi
    if [ -f "src-tauri/target/release/bundle/rpm/*.rpm" ]; then
        cp src-tauri/target/release/bundle/rpm/*.rpm ../../dist/
    fi
    if [ -f "src-tauri/target/release/bundle/appimage/*.AppImage" ]; then
        cp src-tauri/target/release/bundle/appimage/*.AppImage ../../dist/
    fi
fi

# Generate checksums
echo "🔐 Generating checksums..."
cd ../../dist
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum *.* > checksums.txt 2>/dev/null || true
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 *.* > checksums.txt 2>/dev/null || true
fi

echo "✅ Build complete! Installers are available in the dist/ folder."
echo "📋 Checksums have been generated in dist/checksums.txt"

# List generated files
echo "📁 Generated files:"
ls -la *.dmg *.msi *.deb *.rpm *.AppImage *.exe *.app.tar.gz 2>/dev/null || echo "No installer packages found - run 'cargo tauri build' first"
