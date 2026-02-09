#!/bin/bash
set -e

# Build script for generating installer packages
# This script builds the Decentralized Browser for all supported platforms

echo "🚀 Building Decentralized Browser Installers..."

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
mkdir -p dist
rm -f dist/*.dmg dist/*.msi dist/*.deb dist/*.rpm dist/*.AppImage dist/*.exe dist/*.app.tar.gz 2>/dev/null || true

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
    if ls ../../target/release/bundle/dmg/*.dmg >/dev/null 2>&1; then
        cp ../../target/release/bundle/dmg/*.dmg ../../dist/
    fi
    if ls ../../target/release/bundle/macos/*.app >/dev/null 2>&1; then
        tar -czf ../../dist/decentralized-browser-v0.1.0.app.tar.gz -C ../../target/release/bundle/macos/ *.app
    fi
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    # Windows
    if ls ../../target/release/bundle/msi/*.msi >/dev/null 2>&1; then
        cp ../../target/release/bundle/msi/*.msi ../../dist/
    fi
    if ls ../../target/release/*.exe >/dev/null 2>&1; then
        cp ../../target/release/*.exe ../../dist/decentralized-browser-v0.1.0.exe
    fi
else
    # Linux
    if ls ../../target/release/bundle/deb/*.deb >/dev/null 2>&1; then
        cp ../../target/release/bundle/deb/*.deb ../../dist/
    fi
    if ls ../../target/release/bundle/rpm/*.rpm >/dev/null 2>&1; then
        cp ../../target/release/bundle/rpm/*.rpm ../../dist/
    fi
    if ls ../../target/release/bundle/appimage/*.AppImage >/dev/null 2>&1; then
        cp ../../target/release/bundle/appimage/*.AppImage ../../dist/
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
