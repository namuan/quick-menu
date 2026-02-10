#!/bin/bash

# QuickMenu Build and Install Script
# This script builds the QuickMenu application and installs it to ~/Applications

set -e

echo "🖱️  QuickMenu Build Script"
echo "=========================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
APP_NAME="QuickMenu"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="$SCRIPT_DIR/.build"
RELEASE_BINARY="$BUILD_DIR/release/QuickMenu"
INSTALL_DIR="$HOME/Applications"

echo "📁 Project directory: $SCRIPT_DIR"
echo "📦 Build directory: $BUILD_DIR"
echo "🎯 Install directory: $INSTALL_DIR"
echo ""

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
rm -rf "$APP_BUNDLE"

echo "🔨 Building QuickMenu (this may take a minute)..."

# Build using swift build
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# Check if binary exists
if [ ! -f "$RELEASE_BINARY" ]; then
    echo "❌ Could not find built binary at $RELEASE_BINARY"
    exit 1
fi

# Create app bundle structure
echo "📦 Creating app bundle..."
APP_CONTENTS="$SCRIPT_DIR/$APP_BUNDLE/Contents"
mkdir -p "$APP_CONTENTS/MacOS"
mkdir -p "$APP_CONTENTS/Resources"

# Copy executable
cp "$RELEASE_BINARY" "$APP_CONTENTS/MacOS/QuickMenu"

# Copy Info.plist
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_CONTENTS/Info.plist"

# Make sure the Info.plist has the correct executable name
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable QuickMenu" "$APP_CONTENTS/Info.plist" 2>/dev/null || true

echo "✅ App bundle created!"
echo ""

# Sign the app (ad-hoc signing)
echo "🔏 Signing app bundle..."
codesign --force --deep --sign - "$SCRIPT_DIR/$APP_BUNDLE"

echo "✅ App signed!"
echo ""

# Install to ~/Applications
echo "📥 Installing to $INSTALL_DIR..."

# Create Applications folder if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_BUNDLE" ]; then
    echo "   Removing old version..."
    rm -rf "$INSTALL_DIR/$APP_BUNDLE"
fi

# Copy new version
cp -R "$SCRIPT_DIR/$APP_BUNDLE" "$INSTALL_DIR/"

echo "✅ Installed to $INSTALL_DIR/$APP_BUNDLE"
echo ""

# Cleanup build directory
echo "🧹 Cleaning up build files..."
rm -rf "$BUILD_DIR"
rm -rf "$SCRIPT_DIR/$APP_BUNDLE"

echo ""
echo "🎉 Installation complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Open $INSTALL_DIR/$APP_BUNDLE"
echo "      Or run: open '$INSTALL_DIR/$APP_BUNDLE'"
echo ""
echo "   2. Grant Accessibility permissions when prompted"
echo ""
echo "   3. Usage:"
echo "      • Press Command + Shift + M to show/hide menu at cursor"
echo "      • Click the 🖱️ icon in the status bar"
echo ""
echo "⚠️  Note: You may need to allow the app in:"
echo "      System Settings > Privacy & Security > Accessibility"
echo ""
