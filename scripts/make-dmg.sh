#!/usr/bin/env bash
set -euo pipefail

# Package the built app as an installer disk image.
#
# Usage: ./scripts/make-dmg.sh [path/to/Notchshell.app]
#
# Produces build/Notchshell-<version>.dmg: a window holding the app and an alias to
# /Applications, laid out over a backdrop that says to drag one onto the other. That
# drag *is* the install — macOS apps are self-contained bundles, so a .pkg would only
# wrap the same copy in a wizard that then asks for an admin password it does not need.
#
# Run scripts/build-install.sh first; this packages what that produced rather than
# building anything itself.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
source "$SCRIPT_DIR/_toolchain.sh"

APP="${1:-$PROJECT_ROOT/build/Notchshell.app}"
VOLUME_NAME="Notchshell"

if [ ! -d "$APP" ]; then
    echo "no app bundle at $APP — run scripts/build-install.sh first" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$PROJECT_ROOT/build/Notchshell-$VERSION.dmg"

STAGE="$(mktemp -d)"
SCRATCH="$(mktemp -d)"
DEVICE=""
cleanup() {
    [ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -quiet -force 2>/dev/null || true
    rm -rf "$STAGE" "$SCRATCH"
}
trap cleanup EXIT

# ── Stage the contents ────────────────────────────────────────────────────────
echo "==> Staging $VOLUME_NAME $VERSION..."
cp -R "$APP" "$STAGE/Notchshell.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
swift "$SCRIPT_DIR/make-dmg-background.swift" "$SCRATCH/bg.png" "$SCRATCH/bg@2x.png" >/dev/null
# Finder reads the backdrop's pixel size as its point size, so a Retina-sharp backdrop
# cannot just be a bigger PNG. A multi-representation TIFF carries both scales at once.
tiffutil -cathidpicheck "$SCRATCH/bg.png" "$SCRATCH/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

# Volume icon, so the mounted disk and the .dmg itself carry the app's mark.
cp "$PROJECT_ROOT/Notchshell/Resources/Notchshell.icns" "$STAGE/.VolumeIcon.icns"

# ── Build a writable image, dress it, then compress ───────────────────────────
# Sized from the payload with slack: hdiutil cannot grow an image mid-layout, and a
# too-tight image fails only once Finder writes the .DS_Store.
SIZE_KB=$(( $(du -sk "$STAGE" | cut -f1) + 40000 ))

echo "==> Creating image..."
rm -f "$OUT" "$SCRATCH/rw.dmg"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW \
    -size "${SIZE_KB}k" "$SCRATCH/rw.dmg"

DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$SCRATCH/rw.dmg" \
    | grep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOLUME_NAME"

# Give the volume a moment to appear before Finder is asked about it.
for _ in $(seq 1 20); do [ -d "$MOUNT" ] && break; sleep 0.2; done
[ -d "$MOUNT" ] || { echo "volume did not mount at $MOUNT" >&2; exit 1; }

echo "==> Laying out the window..."
# The icon positions here must match the slots the backdrop was drawn around; see
# leftSlot/rightSlot in make-dmg-background.swift.
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- Content area ends up 640x400; the bounds include the title bar.
        set the bounds of container window to {200, 140, 840, 580}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "Notchshell.app" of container window to {170, 218}
        set position of item "Applications" of container window to {470, 218}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Custom-icon bit, so .VolumeIcon.icns is actually used.
SetFile -a C "$MOUNT" 2>/dev/null || true
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

hdiutil detach "$DEVICE" -quiet
DEVICE=""

echo "==> Compressing..."
hdiutil convert "$SCRATCH/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT"

# Sign the image if a Developer ID is on this machine. Ad-hoc signing a .dmg buys
# nothing — Gatekeeper treats it the same as unsigned — so it is skipped rather than
# faked. The first-launch workaround belongs in the release notes, not on the backdrop.
IDENTITY="Developer ID Application: <your identity>"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "==> Signing image..."
    codesign --force --sign "$IDENTITY" "$OUT"
else
    echo "==> Developer ID not found; leaving the image unsigned (not notarized)."
fi

echo "==> Wrote $OUT ($(du -h "$OUT" | cut -f1))"
