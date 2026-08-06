#!/usr/bin/env bash
set -euo pipefail

# Build notchshell, sign it, and install to /Applications.
#
# Usage: ./scripts/build-install.sh [--universal] [--dev]
#
#   --universal  build arm64 + x86_64 instead of arm64 only
#   --dev        install alongside an existing install as notchshell_dev.app,
#                for when you need to run a build without replacing the one you
#                depend on day to day

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/Notchshell.app"
ENTITLEMENTS="$PROJECT_ROOT/Hakuke/Resources/notchshell.entitlements"
BINARY="$APP_BUNDLE/Contents/MacOS/Notchshell"
SIGNING_IDENTITY="Developer ID Application: <your identity>"

cd "$PROJECT_ROOT"
source "$SCRIPT_DIR/_toolchain.sh"

UNIVERSAL=0
SIDE_BY_SIDE=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --dev)       SIDE_BY_SIDE=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [ "$UNIVERSAL" = 1 ]; then
    echo "==> Building universal release (arm64 + x86_64)..."
    swift build --build-system xcode -c release --arch arm64 --arch x86_64
else
    echo "==> Building release (arm64)..."
    swift build --build-system xcode -c release --arch arm64
fi

echo "==> Copying binary..."
# The bundle skeleton is reused across builds, so prune anything left in MacOS/ from
# an earlier product name. codesign rejects a bundle whose MacOS/ holds an executable
# other than CFBundleExecutable ("invalid Info.plist (plist or signature have been
# modified)"), which is how the Hakuke -> notchshell rename first surfaced.
mkdir -p "$(dirname "$BINARY")"
find "$(dirname "$BINARY")" -mindepth 1 -maxdepth 1 ! -name "$(basename "$BINARY")" -exec rm -rf {} +
cp .build/apple/Products/Release/Hakuke "$BINARY"   # SPM target is still named Hakuke

echo "==> Copying Info.plist..."
cp "$PROJECT_ROOT/Hakuke/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Copying icon..."
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$PROJECT_ROOT/Hakuke/Resources/Notchshell.icns" "$RESOURCES_DIR/" 2>/dev/null || true

echo "==> Copying bundled theme catalog..."
# Ghostty looks for <resources-dir>/themes, so the catalog lands under
# Contents/Resources/ghostty and GHOSTTY_RESOURCES_DIR points at that directory.
# Regenerate the source with scripts/fetch-themes.sh.
GHOSTTY_RES_DIR="$RESOURCES_DIR/ghostty"
rm -rf "$GHOSTTY_RES_DIR/themes"
mkdir -p "$GHOSTTY_RES_DIR/themes"
cp -R "$PROJECT_ROOT/vendor/themes/themes/." "$GHOSTTY_RES_DIR/themes/"
cp "$PROJECT_ROOT/vendor/themes/LICENSE" "$GHOSTTY_RES_DIR/THEMES-LICENSE"
echo "    $(find "$GHOSTTY_RES_DIR/themes" -type f | wc -l | tr -d ' ') themes"

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

INSTALL_NAME="Notchshell"
if [ "$SIDE_BY_SIDE" = 1 ]; then
    INSTALL_NAME="Notchshell_dev"
fi

echo "==> Installing to /Applications/${INSTALL_NAME}.app..."
killall "$INSTALL_NAME" 2>/dev/null || true
sleep 0.3
rm -rf "/Applications/${INSTALL_NAME}.app"
cp -R "$APP_BUNDLE" "/Applications/${INSTALL_NAME}.app"

if [ "$SIDE_BY_SIDE" = 1 ]; then
    # Give the side-by-side copy its own executable name so the two show up
    # distinctly in Activity Monitor and killall targets the right one.
    mv "/Applications/${INSTALL_NAME}.app/Contents/MacOS/Notchshell" \
       "/Applications/${INSTALL_NAME}.app/Contents/MacOS/${INSTALL_NAME}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${INSTALL_NAME}" \
        "/Applications/${INSTALL_NAME}.app/Contents/Info.plist"
fi

echo "==> Installed: /Applications/${INSTALL_NAME}.app"

echo "Done."
