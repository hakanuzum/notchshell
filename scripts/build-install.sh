#!/usr/bin/env bash
set -euo pipefail

# Build Maquake, sign it, and optionally install to /Applications.
# Usage: ./scripts/build-install.sh [--install]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/Hakuke.app"
ENTITLEMENTS="$PROJECT_ROOT/Hakuke/Resources/Hakuke.entitlements"
BINARY="$APP_BUNDLE/Contents/MacOS/Hakuke"
SIGNING_IDENTITY="Developer ID Application: <your identity>"

cd "$PROJECT_ROOT"

ARCH="${1:---arch arm64}"
if [ "$ARCH" = "--universal" ]; then
    echo "==> Building universal release (arm64 + x86_64)..."
    swift build --build-system xcode -c release --arch arm64 --arch x86_64
else
    echo "==> Building release (arm64)..."
    swift build --build-system xcode -c release --arch arm64
fi

echo "==> Copying binary..."
cp .build/apple/Products/Release/Hakuke "$BINARY"

echo "==> Copying Info.plist..."
cp "$PROJECT_ROOT/Hakuke/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Copying icon..."
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$PROJECT_ROOT/Hakuke/Resources/hakuke.icns" "$RESOURCES_DIR/" 2>/dev/null || true

echo "==> Copying resource bundles..."
for bundle in .build/apple/Products/Release/*.bundle; do
    [ -d "$bundle" ] || continue
    # Skip bundles without Info.plist — they can't be codesigned
    [ -f "$bundle/Info.plist" ] || [ -f "$bundle/Contents/Info.plist" ] || continue
    name="$(basename "$bundle")"
    rm -rf "$RESOURCES_DIR/$name"
    cp -R "$bundle" "$RESOURCES_DIR/$name"
    echo "    $name"
done

echo "==> Removing stale bundles from app root..."
for bundle in "$APP_BUNDLE"/*.bundle; do
    [ -d "$bundle" ] || continue
    rm -rf "$bundle"
done

echo "==> Embedding Sparkle.framework..."
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
    cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"
else
    echo "WARNING: Sparkle.framework not found at $SPARKLE_SRC"
fi

echo "==> Fixing rpath for embedded frameworks..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY" 2>/dev/null || true

# Check if signing identity is available; fall back to ad-hoc for dev builds
if security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    SIGN_ID="$SIGNING_IDENTITY"
    SIGN_OPTS="--options runtime"
    echo "==> Signing (inside-out) with: $SIGN_ID"
else
    SIGN_ID="-"
    SIGN_OPTS=""
    echo "==> Signing (ad-hoc, Developer ID not found)"
fi

# Sign resource bundles in Resources/
for bundle in "$APP_BUNDLE"/Contents/Resources/*.bundle; do
    [ -d "$bundle" ] || continue
    codesign --force --sign "$SIGN_ID" "$bundle"
done

# Sign Sparkle components inside-out
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Sign main app bundle last
codesign --force --sign "$SIGN_ID" \
    $SIGN_OPTS \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
echo "==> Signed and verified: $APP_BUNDLE"

# Install as Hakuke_dev.app to avoid conflicting with brew-installed Hakuke.app
INSTALL_NAME="Hakuke_dev"
echo "==> Installing to /Applications/${INSTALL_NAME}.app..."
killall "$INSTALL_NAME" 2>/dev/null || true
sleep 0.3
rm -rf "/Applications/${INSTALL_NAME}.app"
cp -R "$APP_BUNDLE" "/Applications/${INSTALL_NAME}.app"
mv "/Applications/${INSTALL_NAME}.app/Contents/MacOS/Hakuke" "/Applications/${INSTALL_NAME}.app/Contents/MacOS/${INSTALL_NAME}"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${INSTALL_NAME}" "/Applications/${INSTALL_NAME}.app/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${INSTALL_NAME}" "/Applications/${INSTALL_NAME}.app/Contents/Info.plist"
echo "==> Installed: /Applications/${INSTALL_NAME}.app"

echo "Done."
