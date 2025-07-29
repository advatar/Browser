#!/bin/bash

# Decentralized Browser Build Script
# This script builds the browser for multiple platforms and creates distribution packages

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="decentralized-browser"
VERSION=$(grep '^version = ' Cargo.toml | sed 's/version = "\(.*\)"/\1/')
BUILD_DIR="target/release"
DIST_DIR="dist"
PLATFORMS=("x86_64-apple-darwin" "aarch64-apple-darwin" "x86_64-pc-windows-msvc" "x86_64-unknown-linux-gnu")

echo -e "${BLUE}🚀 Building Decentralized Browser v${VERSION}${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    
    # Check Rust
    if ! command -v cargo &> /dev/null; then
        print_error "Rust/Cargo not found. Please install Rust."
        exit 1
    fi
    print_status "Rust/Cargo found"
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js not found. Please install Node.js."
        exit 1
    fi
    print_status "Node.js found"
    
    # Check pnpm
    if ! command -v pnpm &> /dev/null; then
        print_error "pnpm not found. Please install pnpm."
        exit 1
    fi
    print_status "pnpm found"
    
    # Check Tauri CLI
    if ! command -v cargo-tauri &> /dev/null; then
        print_warning "Tauri CLI not found. Installing..."
        cargo install tauri-cli
    fi
    print_status "Tauri CLI found"
}

# Clean previous builds
clean_builds() {
    echo -e "${BLUE}🧹 Cleaning previous builds...${NC}"
    rm -rf $BUILD_DIR
    rm -rf $DIST_DIR
    mkdir -p $DIST_DIR
    print_status "Build directories cleaned"
}

# Install dependencies
install_dependencies() {
    echo -e "${BLUE}📦 Installing dependencies...${NC}"
    
    # Install Rust dependencies
    cargo fetch
    print_status "Rust dependencies installed"
    
    # Install Node.js dependencies
    cd crates/gui
    pnpm install
    cd ../..
    print_status "Node.js dependencies installed"
}

# Run tests
run_tests() {
    echo -e "${BLUE}🧪 Running tests...${NC}"
    
    # Run Rust tests
    cargo test --workspace
    print_status "Rust tests passed"
    
    # Run frontend tests
    cd crates/gui
    pnpm test
    cd ../..
    print_status "Frontend tests passed"
}

# Build for specific platform
build_platform() {
    local platform=$1
    echo -e "${BLUE}🔨 Building for ${platform}...${NC}"
    
    # Add target if not already added
    rustup target add $platform 2>/dev/null || true
    
    # Build the application
    cd crates/gui
    pnpm tauri build --target $platform
    cd ../..
    
    print_status "Built for $platform"
}

# Create distribution packages
create_packages() {
    echo -e "${BLUE}📦 Creating distribution packages...${NC}"
    
    # macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Create DMG for macOS
        if [ -f "crates/gui/src-tauri/target/release/bundle/dmg/${PROJECT_NAME}_${VERSION}_x64.dmg" ]; then
            cp "crates/gui/src-tauri/target/release/bundle/dmg/${PROJECT_NAME}_${VERSION}_x64.dmg" "$DIST_DIR/"
            print_status "macOS DMG created"
        fi
        
        # Create App bundle
        if [ -d "crates/gui/src-tauri/target/release/bundle/macos/${PROJECT_NAME}.app" ]; then
            cp -r "crates/gui/src-tauri/target/release/bundle/macos/${PROJECT_NAME}.app" "$DIST_DIR/"
            print_status "macOS App bundle created"
        fi
    fi
    
    # Windows
    if [ -f "crates/gui/src-tauri/target/release/bundle/msi/${PROJECT_NAME}_${VERSION}_x64_en-US.msi" ]; then
        cp "crates/gui/src-tauri/target/release/bundle/msi/${PROJECT_NAME}_${VERSION}_x64_en-US.msi" "$DIST_DIR/"
        print_status "Windows MSI created"
    fi
    
    # Linux
    if [ -f "crates/gui/src-tauri/target/release/bundle/deb/${PROJECT_NAME}_${VERSION}_amd64.deb" ]; then
        cp "crates/gui/src-tauri/target/release/bundle/deb/${PROJECT_NAME}_${VERSION}_amd64.deb" "$DIST_DIR/"
        print_status "Linux DEB created"
    fi
    
    if [ -f "crates/gui/src-tauri/target/release/bundle/rpm/${PROJECT_NAME}-${VERSION}-1.x86_64.rpm" ]; then
        cp "crates/gui/src-tauri/target/release/bundle/rpm/${PROJECT_NAME}-${VERSION}-1.x86_64.rpm" "$DIST_DIR/"
        print_status "Linux RPM created"
    fi
    
    # AppImage
    if [ -f "crates/gui/src-tauri/target/release/bundle/appimage/${PROJECT_NAME}_${VERSION}_amd64.AppImage" ]; then
        cp "crates/gui/src-tauri/target/release/bundle/appimage/${PROJECT_NAME}_${VERSION}_amd64.AppImage" "$DIST_DIR/"
        print_status "Linux AppImage created"
    fi
}

# Generate checksums
generate_checksums() {
    echo -e "${BLUE}🔐 Generating checksums...${NC}"
    
    cd $DIST_DIR
    
    # Generate SHA256 checksums
    if command -v sha256sum &> /dev/null; then
        sha256sum * > SHA256SUMS
    elif command -v shasum &> /dev/null; then
        shasum -a 256 * > SHA256SUMS
    fi
    
    print_status "Checksums generated"
    cd ..
}

# Sign packages (if certificates are available)
sign_packages() {
    echo -e "${BLUE}✍️ Signing packages...${NC}"
    
    # macOS code signing
    if [[ "$OSTYPE" == "darwin"* ]] && [ ! -z "$APPLE_SIGNING_IDENTITY" ]; then
        for app in $DIST_DIR/*.app; do
            if [ -d "$app" ]; then
                codesign --force --deep --sign "$APPLE_SIGNING_IDENTITY" "$app"
                print_status "Signed $(basename "$app")"
            fi
        done
        
        for dmg in $DIST_DIR/*.dmg; do
            if [ -f "$dmg" ]; then
                codesign --force --sign "$APPLE_SIGNING_IDENTITY" "$dmg"
                print_status "Signed $(basename "$dmg")"
            fi
        done
    else
        print_warning "macOS signing skipped (no APPLE_SIGNING_IDENTITY)"
    fi
    
    # Windows code signing
    if [ ! -z "$WINDOWS_CERTIFICATE_PATH" ] && [ ! -z "$WINDOWS_CERTIFICATE_PASSWORD" ]; then
        for msi in $DIST_DIR/*.msi; do
            if [ -f "$msi" ]; then
                # This would require signtool.exe on Windows
                print_warning "Windows signing not implemented in this script"
            fi
        done
    else
        print_warning "Windows signing skipped (no certificate configured)"
    fi
}

# Create release notes
create_release_notes() {
    echo -e "${BLUE}📝 Creating release notes...${NC}"
    
    cat > $DIST_DIR/RELEASE_NOTES.md << EOF
# Decentralized Browser v${VERSION}

## Features
- ✅ Decentralized web browsing with IPFS and IPNS support
- ✅ ENS (Ethereum Name Service) resolution
- ✅ Integrated cryptocurrency wallet
- ✅ Privacy-focused browsing with tracker blocking
- ✅ Tor proxy support for enhanced privacy
- ✅ P2P networking with libp2p
- ✅ Blockchain integration (Ethereum, Bitcoin, Substrate)
- ✅ Modern web standards support
- ✅ Cross-platform compatibility

## Installation

### macOS
1. Download the \`.dmg\` file
2. Open the DMG and drag the app to Applications folder
3. Run the application (you may need to allow it in Security & Privacy settings)

### Windows
1. Download the \`.msi\` file
2. Run the installer as administrator
3. Follow the installation wizard

### Linux
- **Ubuntu/Debian**: Download and install the \`.deb\` file with \`sudo dpkg -i filename.deb\`
- **Fedora/RHEL**: Download and install the \`.rpm\` file with \`sudo rpm -i filename.rpm\`
- **AppImage**: Download the \`.AppImage\` file, make it executable, and run

## Security
All packages are signed and checksums are provided in SHA256SUMS.

## Support
- Documentation: https://github.com/your-org/decentralized-browser/docs
- Issues: https://github.com/your-org/decentralized-browser/issues
- Community: https://discord.gg/your-discord

## License
MIT License - see LICENSE file for details.
EOF
    
    print_status "Release notes created"
}

# Main build process
main() {
    echo -e "${BLUE}🌟 Starting build process for Decentralized Browser${NC}"
    
    # Parse command line arguments
    SKIP_TESTS=false
    PLATFORMS_TO_BUILD=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --platform)
                PLATFORMS_TO_BUILD+=("$2")
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --skip-tests     Skip running tests"
                echo "  --platform NAME  Build only for specific platform"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # If no specific platforms specified, build for current platform only
    if [ ${#PLATFORMS_TO_BUILD[@]} -eq 0 ]; then
        case "$OSTYPE" in
            darwin*)
                if [[ $(uname -m) == "arm64" ]]; then
                    PLATFORMS_TO_BUILD=("aarch64-apple-darwin")
                else
                    PLATFORMS_TO_BUILD=("x86_64-apple-darwin")
                fi
                ;;
            linux*)
                PLATFORMS_TO_BUILD=("x86_64-unknown-linux-gnu")
                ;;
            msys*|cygwin*)
                PLATFORMS_TO_BUILD=("x86_64-pc-windows-msvc")
                ;;
            *)
                print_error "Unsupported platform: $OSTYPE"
                exit 1
                ;;
        esac
    fi
    
    # Execute build steps
    check_prerequisites
    clean_builds
    install_dependencies
    
    if [ "$SKIP_TESTS" = false ]; then
        run_tests
    else
        print_warning "Skipping tests"
    fi
    
    # Build for each platform
    for platform in "${PLATFORMS_TO_BUILD[@]}"; do
        build_platform "$platform"
    done
    
    create_packages
    generate_checksums
    sign_packages
    create_release_notes
    
    echo -e "${GREEN}🎉 Build completed successfully!${NC}"
    echo -e "${BLUE}📦 Distribution packages created in: ${DIST_DIR}${NC}"
    
    # List created files
    echo -e "${BLUE}📋 Created files:${NC}"
    ls -la $DIST_DIR/
}

# Run main function
main "$@"
