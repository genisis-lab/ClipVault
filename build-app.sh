#!/bin/bash
# Builds ClipVault in release mode and assembles a .app bundle that can be
# launched from the Finder / placed in /Applications.
set -euo pipefail

APP_NAME="ClipVault"
BUNDLE_ID="com.clipvault.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Generating app icon"
ICON_PNG="$(mktemp -t clipvault-icon).png"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
if swift "$ROOT/generate-icon.swift" "$ICON_PNG" >/dev/null 2>&1; then
    for size in 16 32 64 128 256 512 1024; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1
    done
    # Retina (@2x) variants expected by iconutil.
    cp "$ICONSET_DIR/icon_32x32.png"   "$ICONSET_DIR/icon_16x16@2x.png"   2>/dev/null || true
    cp "$ICONSET_DIR/icon_64x64.png"   "$ICONSET_DIR/icon_32x32@2x.png"   2>/dev/null || true
    cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
    cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
    cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true
    if iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        echo "   icon written to Resources/AppIcon.icns"
    else
        echo "   (iconutil failed; bundle ships without a custom icon)"
    fi
else
    echo "   (icon generation failed; bundle ships without a custom icon)"
fi

echo "==> Ad-hoc code signing (hardened runtime)"
codesign --force --deep --options runtime --sign - "$APP_DIR" 2>/dev/null || \
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || \
    echo "   (codesign unavailable; bundle still runnable locally)"

echo "==> Done: $APP_DIR"
