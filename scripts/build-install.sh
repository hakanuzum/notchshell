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
ENTITLEMENTS="$PROJECT_ROOT/Notchshell/Resources/notchshell.entitlements"
BINARY="$APP_BUNDLE/Contents/MacOS/Notchshell"
# Developer ID to sign with, if one is present. Set NOTCHSHELL_SIGNING_IDENTITY in the
# environment to your own "Developer ID Application: … (TEAMID)" to produce a
# distributable build; left unset, the script signs ad-hoc, which is all a local build
# or an unnotarized release needs. Not hardcoded: a signing identity names a specific
# Apple account and does not belong in a public repo.
SIGNING_IDENTITY="${NOTCHSHELL_SIGNING_IDENTITY:-}"

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

# libghostty is built from the pinned submodule rather than downloaded. The
# xcframework used to be a symlink into another checkout on the original author's
# machine, so a fresh clone could not build at all.
if [ ! -d "$PROJECT_ROOT/vendor/ghostty/macos/GhosttyKit.xcframework" ]; then
    echo "==> GhosttyKit.xcframework missing; building it first..."
    "$SCRIPT_DIR/build-ghostty.sh"
fi

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
# modified)"), which is how the first product rename surfaced.
mkdir -p "$(dirname "$BINARY")"
find "$(dirname "$BINARY")" -mindepth 1 -maxdepth 1 \
    ! -name "$(basename "$BINARY")" ! -name "notchshell-cli" -exec rm -rf {} +
cp .build/apple/Products/Release/Notchshell "$BINARY"

echo "==> Copying Info.plist..."
cp "$PROJECT_ROOT/Notchshell/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Copying icon..."
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp "$PROJECT_ROOT/Notchshell/Resources/Notchshell.icns" "$RESOURCES_DIR/"
# Menu-bar template image. This app has no Dock tile, so this is the icon people
# actually see; regenerate it with scripts/make-menubar-icon.swift.
cp "$PROJECT_ROOT/Notchshell/Resources/NotchshellMenuBar.png" "$RESOURCES_DIR/"

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

echo "==> Copying shell integration..."
# Ghostty's `shell-integration = detect` injects OSC 7 (working directory) and OSC 133
# (prompt marks) into bash/zsh/fish by sourcing scripts it finds under
# <resources-dir>/shell-integration. Without them nothing is injected: the shell never
# reports where it is, GHOSTTY_ACTION_PWD never fires, and a tab cannot follow `cd` —
# it was left showing whatever the prompt happened to write as the window title. The
# scripts are copied from the submodule source (git-tracked, always present) rather
# than zig-out, which is a build artifact and may be absent on a fresh checkout.
rm -rf "$GHOSTTY_RES_DIR/shell-integration"
mkdir -p "$GHOSTTY_RES_DIR/shell-integration"
cp -R "$PROJECT_ROOT/vendor/ghostty/src/shell-integration/." "$GHOSTTY_RES_DIR/shell-integration/"
rm -f "$GHOSTTY_RES_DIR/shell-integration/README.md"
echo "    $(find "$GHOSTTY_RES_DIR/shell-integration" -type d -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') shells"

echo "==> Building Finder extension..."
# Built here rather than by SPM, which cannot produce an `.appex`. An app extension is
# a bundle with an `XPC!` package type and an `NSExtension` dictionary, and its
# executable is entered through `NSExtensionMain` instead of `main()` — hence the
# linker's `-e`. Everything else is an ordinary Swift compile.
FINDER_SRC="$PROJECT_ROOT/Notchshell/Resources/finder-extension"
APPEX="$APP_BUNDLE/Contents/PlugIns/NotchshellFinder.appex"
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS"
cp "$FINDER_SRC/Info.plist" "$APPEX/Contents/Info.plist"
# Versions come from the app rather than being written twice. They drifted once
# already between Info.plist and the Help text; two version numbers for one build is
# the same trap with a shorter fuse.
for key in CFBundleShortVersionString CFBundleVersion; do
    value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP_BUNDLE/Contents/Info.plist")
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$APPEX/Contents/Info.plist"
done
xcrun swiftc -target arm64-apple-macos14.0 -O \
    -framework Cocoa -framework FinderSync \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$APPEX/Contents/MacOS/NotchshellFinder" \
    "$FINDER_SRC/FinderSync.swift"
# The mark goes inside the extension, not read from the app: a Finder Sync extension is
# sandboxed and the app's Resources are not its to open.
mkdir -p "$APPEX/Contents/Resources"
cp "$FINDER_SRC/NotchshellFinderToolbar.png" \
   "$APPEX/Contents/Resources/NotchshellFinderToolbar.png"

echo "==> Copying command line tool..."
# Lives beside the app binary, the way Ghostty ships its own CLI. Settings links it
# onto PATH; keeping the real file in the bundle means the link survives updates and
# disappears when the app is deleted.
cp "$PROJECT_ROOT/Notchshell/Resources/cli/notchshell-cli" "$APP_BUNDLE/Contents/MacOS/notchshell-cli"
chmod +x "$APP_BUNDLE/Contents/MacOS/notchshell-cli"

echo "==> Compiling terminfo..."
# libghostty announces TERM=xterm-ghostty, which no OS ships. Without this every
# ncurses program in the terminal is broken; it only worked during development
# because another Ghostty-based terminal had leaked TERMINFO into the environment.
# The database is a sibling of the resources directory, which is where libghostty
# looks for it. See vendor/terminfo/README.md.
TERMINFO_DIR="$RESOURCES_DIR/terminfo"
rm -rf "$TERMINFO_DIR"
mkdir -p "$TERMINFO_DIR"
# tic warns about the description field on older versions; the output is still correct.
tic -x -o "$TERMINFO_DIR" "$PROJECT_ROOT/vendor/terminfo/ghostty.terminfo" 2>/dev/null || {
    echo "ERROR: tic failed to compile vendor/terminfo/ghostty.terminfo" >&2
    exit 1
}
TERMINFO="$TERMINFO_DIR" infocmp xterm-ghostty >/dev/null 2>&1 || {
    echo "ERROR: compiled terminfo does not resolve xterm-ghostty" >&2
    exit 1
}
echo "    xterm-ghostty"

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

# Sign with the configured Developer ID if it is set and actually present in the
# keychain; otherwise ad-hoc. The identity must be non-empty before grep — an empty
# pattern matches every line, so a blank identity would otherwise look "found" and then
# hand codesign an empty name.
if [ -n "$SIGNING_IDENTITY" ] && security find-identity -v -p codesigning | grep -qF "$SIGNING_IDENTITY"; then
    SIGN_ID="$SIGNING_IDENTITY"
    SIGN_OPTS="--options runtime"
    echo "==> Signing (inside-out) with: $SIGN_ID"
else
    SIGN_ID="-"
    SIGN_OPTS=""
    echo "==> Signing (ad-hoc; set NOTCHSHELL_SIGNING_IDENTITY for a Developer ID build)"
fi

# The extension is nested code, and macOS refuses to load an app extension that is not
# sandboxed — so it carries its own entitlements rather than the app's, which are the
# opposite of sandboxed on purpose.
codesign --force --sign "$SIGN_ID" $SIGN_OPTS \
    --entitlements "$PROJECT_ROOT/Notchshell/Resources/finder-extension/finder.entitlements" \
    "$APP_BUNDLE/Contents/PlugIns/NotchshellFinder.appex"

# Sign resource bundles in Resources/
for bundle in "$APP_BUNDLE"/Contents/Resources/*.bundle; do
    [ -d "$bundle" ] || continue
    codesign --force --sign "$SIGN_ID" "$bundle"
done

# The command line tool sits in MacOS/, so codesign treats it as nested code and
# refuses to verify the bundle until it is signed in its own right.
codesign --force --sign "$SIGN_ID" "$APP_BUNDLE/Contents/MacOS/notchshell-cli"

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
