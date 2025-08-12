#!/bin/bash
set -e

# Create .dmg installer for Decentralized Browser
# This script creates a macOS .dmg installer package

echo "🚀 Creating Decentralized Browser .dmg installer..."

# Ensure we're in the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Configuration
APP_NAME="Decentralized Browser"
APP_VERSION="0.1.0"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
DMG_VOLUME_NAME="${APP_NAME}"
BACKGROUND_IMAGE_PATH="scripts/dmg-background.png"
ICON_PATH="crates/gui/icons/icon.icns"

# Create dist directory if it doesn't exist
mkdir -p dist

# Clean previous .dmg
rm -f "dist/${DMG_NAME}"

# Create temporary directory for .dmg contents
echo "📁 Creating temporary directory structure..."
TEMP_DIR=$(mktemp -d)
DMG_DIR="${TEMP_DIR}/dmg"
mkdir -p "${DMG_DIR}"

# Create Applications shortcut
ln -s /Applications "${DMG_DIR}/Applications"

# Create .app bundle directory structure
APP_DIR="${DMG_DIR}/${APP_NAME}.app"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>decentralized-browser</string>
    <key>CFBundleIdentifier</key>
    <string>com.decentralized.browser</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.12</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

# Create a simple executable wrapper
cat > "${APP_DIR}/Contents/MacOS/decentralized-browser" << 'EOF'
#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

# Check if we have a built executable
if [[ -f "${APP_DIR}/../../target/release/gui" ]]; then
    exec "${APP_DIR}/../../target/release/gui"
elif [[ -f "${APP_DIR}/../../target/debug/gui" ]]; then
    exec "${APP_DIR}/../../target/debug/gui"
elif [[ -f "${APP_DIR}/../../target/release/decentralized-browser" ]]; then
    exec "${APP_DIR}/../../target/release/decentralized-browser"
elif [[ -f "${APP_DIR}/../../target/debug/decentralized-browser" ]]; then
    exec "${APP_DIR}/../../target/debug/decentralized-browser"
elif [[ -f "${APP_DIR}/../../target/release/browser" ]]; then
    exec "${APP_DIR}/../../target/release/browser"
elif [[ -f "${APP_DIR}/../../target/debug/browser" ]]; then
    exec "${APP_DIR}/../../target/debug/browser"
else
    # Fallback: open the web interface
    open "http://localhost:5174"
fi
EOF

chmod +x "${APP_DIR}/Contents/MacOS/decentralized-browser"

# Copy icon if available
if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "${APP_DIR}/Contents/Resources/icon.icns"
    # Update Info.plist to reference the icon
    plutil -replace CFBundleIconFile -string "icon.icns" "${APP_DIR}/Contents/Info.plist"
fi

# Create background image if not exists
if [[ ! -f "$BACKGROUND_IMAGE_PATH" ]]; then
    echo "🎨 Creating background image..."
    mkdir -p "$(dirname "$BACKGROUND_IMAGE_PATH")"
    
    # Create a simple background using sips or imagemagick if available
    if command -v sips >/dev/null 2>&1; then
        # Create background using sips (macOS built-in)
        sips -z 400 640 -s format png \
            --out "$BACKGROUND_IMAGE_PATH" \
            <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" 2>/dev/null || true
    else
        # Create a simple text-based background
        convert -size 640x400 xc:none -fill white -stroke black -strokewidth 2 \
            -gravity center -pointsize 24 -annotate +0+0 "Drag ${APP_NAME} to Applications" \
            "$BACKGROUND_IMAGE_PATH" 2>/dev/null || true
    fi
fi

# Calculate DMG size (add some padding)
DMG_SIZE_MB=50

# Create the .dmg file
echo "💿 Creating .dmg file..."
hdiutil create -size ${DMG_SIZE_MB}m -fs HFS+ -volname "$DMG_VOLUME_NAME" -srcfolder "$DMG_DIR" "dist/${DMG_NAME}"

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo "✅ .dmg installer created successfully!"
echo "📁 Location: dist/${DMG_NAME}"
echo "📊 Size: $(du -h "dist/${DMG_NAME}" | cut -f1)"

# Verify the .dmg
echo "🔍 Verifying .dmg..."
hdiutil verify "dist/${DMG_NAME}" || echo "⚠️  Verification completed with warnings"

# Optional: create a signed version if codesign is available
if command -v codesign >/dev/null 2>&1; then
    echo "🔐 Attempting to sign the .dmg..."
    codesign --sign - "dist/${DMG_NAME}" || echo "⚠️  Could not sign .dmg (development signature)"
fi

echo "🎉 .dmg installer is ready!"
echo ""
echo "To test the installer:"
echo "1. Open: open dist/${DMG_NAME}"
echo "2. Drag the app to Applications"
echo "3. Launch from Applications"

# List the generated file
ls -la "dist/${DMG_NAME}"
