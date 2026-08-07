#!/usr/bin/env bash
set -euo pipefail

# Build the Sparkle appcast for a release, signing the DMG with the EdDSA key held in
# the login keychain.
#
# Usage: ./scripts/make-appcast.sh <version>          e.g. 0.3.3
#        ./scripts/make-appcast.sh <version> <dmg>    if the file is not the default
#
# Produces build/appcast/appcast.xml next to a copy of the DMG. Both are then attached
# to the GitHub release for that version — the app's SUFeedURL points at
# releases/latest/download/appcast.xml, and each appcast entry's download URL points at
# that specific release's DMG (releases/download/v<version>/…), so "latest" always
# resolves to the newest signed build.
#
# The private key lives only in the keychain; generate_appcast reads it there. If it is
# missing, run bin/generate_keys once (a new key means re-signing every published DMG
# and updating SUPublicEDKey in Info.plist).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${1:?usage: make-appcast.sh <version> [dmg]}"
DMG="${2:-$PROJECT_ROOT/build/Notchshell-$VERSION.dmg}"
REPO="hakanuzum/notchshell"

if [ ! -f "$DMG" ]; then
    echo "no DMG at $DMG — run scripts/make-dmg.sh first" >&2
    exit 1
fi

TOOLS="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin"
GEN="$TOOLS/generate_appcast"
if [ ! -x "$GEN" ]; then
    echo "generate_appcast not found — build once so SPM fetches Sparkle" >&2
    exit 1
fi

# generate_appcast reads the private key from the keychain; fail early if it is absent
# rather than emit an unsigned feed the app will reject.
if ! "$TOOLS/generate_keys" -p >/dev/null 2>&1; then
    echo "no Sparkle signing key in the keychain — run $TOOLS/generate_keys" >&2
    exit 1
fi

STAGE="$PROJECT_ROOT/build/appcast"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"

# The enclosure URL must point at this version's release asset, not at "latest" — the
# feed itself is fetched from latest, but an entry has to name a concrete file.
"$GEN" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" \
    -o "$STAGE/appcast.xml" \
    "$STAGE"

echo "==> Wrote $STAGE/appcast.xml"
echo
grep -E "sparkle:version|sparkle:edSignature|enclosure url" "$STAGE/appcast.xml" | sed 's/^/    /'
echo
echo "Attach both to the release:"
echo "    gh release upload v$VERSION \"$STAGE/appcast.xml\" \"$DMG\" --repo $REPO --clobber"
