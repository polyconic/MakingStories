#!/bin/bash
# Builds MakingStories.app.
set -euo pipefail

APP_NAME="MakingStories"
BUNDLE_ID="com.gregoregan.makingstories"
VERSION="1.0"
MIN_MACOS="15.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

echo "==> Cleaning"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (arm64, macOS $MIN_MACOS+)"
swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 \
    -target "arm64-apple-macosx$MIN_MACOS" \
    -framework AppKit -framework SwiftUI -framework AVFoundation \
    -framework CoreGraphics -framework CoreMedia -framework Vision -framework UniformTypeIdentifiers \
    "$ROOT"/Sources/*.swift \
    -o "$APP/Contents/MacOS/$APP_NAME"

echo "==> Building icon"
ICONSET="$BUILD/$APP_NAME.iconset"
mkdir -p "$ICONSET" "$BUILD/icons"
swiftc -O "$ROOT/Tools/makeicon.swift" -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/icons" >/dev/null
cp "$BUILD/icons/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$BUILD/icons/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$BUILD/icons/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$BUILD/icons/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$BUILD/icons/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$BUILD/icons/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$BUILD/icons/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$BUILD/icons/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$BUILD/icons/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$BUILD/icons/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Video</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>None</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

rm -rf "$ICONSET" "$BUILD/icons" "$BUILD/makeicon"

echo ""
echo "    App:  $APP"
echo "==> Done"
