#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/ClaudeMonitor"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/ClaudeMonitor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

SWIFT_SOURCES=(
    "$SRC_DIR/main.swift"
    "$SRC_DIR/Log.swift"
    "$SRC_DIR/Config.swift"
    "$SRC_DIR/OAuthClient.swift"
    "$SRC_DIR/LocalHTTPServer.swift"
    "$SRC_DIR/AnthropicAPIClient.swift"
    "$SRC_DIR/StatusFeedClient.swift"
    "$SRC_DIR/StatusItemView.swift"
    "$SRC_DIR/PopoverView.swift"
    "$SRC_DIR/AppDelegate.swift"
)

FRAMEWORKS="-framework Cocoa -framework Security"

echo "🔨 Building Claude Monitor..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

# Copy Info.plist and icon
cp "$SRC_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$SRC_DIR/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

# Build for arm64
swiftc -O -target arm64-apple-macos13.0 \
    -o "$MACOS_DIR/ClaudeMonitor-arm64" \
    "${SWIFT_SOURCES[@]}" $FRAMEWORKS

# Build for x86_64
swiftc -O -target x86_64-apple-macos13.0 \
    -o "$MACOS_DIR/ClaudeMonitor-x86_64" \
    "${SWIFT_SOURCES[@]}" $FRAMEWORKS

# Create universal binary
lipo -create \
    "$MACOS_DIR/ClaudeMonitor-arm64" \
    "$MACOS_DIR/ClaudeMonitor-x86_64" \
    -output "$MACOS_DIR/ClaudeMonitor"

rm "$MACOS_DIR/ClaudeMonitor-arm64" "$MACOS_DIR/ClaudeMonitor-x86_64"

echo "✅ Built: $APP_DIR (universal binary)"
echo ""
echo "Pour lancer:"
echo "  open $APP_DIR"
echo ""
echo "Pour installer:"
echo "  cp -r $APP_DIR /Applications/"
