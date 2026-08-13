#!/usr/bin/env bash
set -euo pipefail

# Point the Homebrew cask at a published release.
#
# Usage: ./scripts/bump-cask.sh                 the version in Info.plist
#        ./scripts/bump-cask.sh <version>       a specific one, e.g. 0.6.6
#        ./scripts/bump-cask.sh --no-push       commit in the tap, leave pushing to you
#
# The cask lives in a second repository, hakanuzum/homebrew-notchshell, checked out
# beside this one. Set NOTCHSHELL_TAP_DIR if it is somewhere else.
#
# The checksum is taken from the *released* DMG, downloaded from GitHub — not from
# build/, and not from the local tap. That is the file `brew install` will fetch, so it
# is the only file whose hash is worth recording. If a local build of the same version
# is present and hashes differently, that is reported: it means what was uploaded is not
# what is on this disk.
#
# Run this after the release exists (step 5 of Releasing in CLAUDE.md), because a cask
# pointing at a tag GitHub does not serve yet is worse than no cask at all.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

REPO="hakanuzum/notchshell"
TAP_DIR="${NOTCHSHELL_TAP_DIR:-$PROJECT_ROOT/../homebrew-notchshell}"
PUSH=1
VERSION=""

for arg in "$@"; do
    case "$arg" in
        --no-push) PUSH=0 ;;
        -*) echo "unknown option: $arg" >&2; exit 1 ;;
        *) VERSION="$arg" ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$PROJECT_ROOT/Notchshell/Resources/Info.plist")"
fi

if [ ! -d "$TAP_DIR/.git" ]; then
    echo "no tap checkout at $TAP_DIR — clone hakanuzum/homebrew-notchshell there," >&2
    echo "or set NOTCHSHELL_TAP_DIR to where it is" >&2
    exit 1
fi
TAP_DIR="$(cd "$TAP_DIR" && pwd)"
CASK="$TAP_DIR/Casks/notchshell.rb"
[ -f "$CASK" ] || { echo "no cask at $CASK" >&2; exit 1; }

ASSET="Notchshell-$VERSION.dmg"

# The cask's url interpolates the version into a release asset path. Fail here rather
# than let brew fail at install time on a 404.
if ! gh release view "v$VERSION" --repo "$REPO" --json assets \
        --jq '.assets[].name' 2>/dev/null | grep -qx "$ASSET"; then
    echo "release v$VERSION has no asset named $ASSET" >&2
    echo "publish the release first, then run this" >&2
    exit 1
fi

echo "==> Fetching $ASSET from v$VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
gh release download "v$VERSION" --repo "$REPO" --pattern "$ASSET" --dir "$STAGE"
SHA="$(shasum -a 256 "$STAGE/$ASSET" | cut -d' ' -f1)"
echo "    $SHA"

LOCAL_DMG="$PROJECT_ROOT/build/$ASSET"
if [ -f "$LOCAL_DMG" ]; then
    LOCAL_SHA="$(shasum -a 256 "$LOCAL_DMG" | cut -d' ' -f1)"
    if [ "$LOCAL_SHA" != "$SHA" ]; then
        echo "!!  build/$ASSET hashes differently ($LOCAL_SHA)."
        echo "!!  The release carries a different file than this build. Recording the"
        echo "!!  released one, which is what users get — but check which is stale."
    fi
fi

# A sed that matches nothing exits 0, which would read as a successful bump. Confirm
# both lines are there before touching the file.
grep -qE '^  version "[^"]+"$' "$CASK" || { echo "no version line in $CASK" >&2; exit 1; }
grep -qE '^  sha256 "[^"]+"$' "$CASK" || { echo "no sha256 line in $CASK" >&2; exit 1; }

OLD_VERSION="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$CASK")"
OLD_SHA="$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "$CASK")"

if [ "$OLD_VERSION" = "$VERSION" ] && [ "$OLD_SHA" = "$SHA" ]; then
    echo "==> Cask already at $VERSION with this checksum; nothing to do"
    exit 0
fi

sed -e "s|^  version \".*\"$|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"$|  sha256 \"$SHA\"|" \
    "$CASK" > "$STAGE/notchshell.rb"
mv "$STAGE/notchshell.rb" "$CASK"
echo "==> Cask $OLD_VERSION -> $VERSION"

if command -v brew >/dev/null 2>&1; then
    brew style "$CASK" >/dev/null || { echo "brew style rejected the cask" >&2; exit 1; }
    echo "==> brew style clean"
fi

git -C "$TAP_DIR" add Casks/notchshell.rb
git -C "$TAP_DIR" commit -q -m "Point the cask at $VERSION"

if [ "$PUSH" = "1" ]; then
    git -C "$TAP_DIR" push -q origin HEAD
    echo "==> Pushed; brew update will pick it up"
    echo
    echo "Verify with:"
    echo "    brew update && brew info --cask notchshell"
else
    echo "==> Committed, not pushed. From $TAP_DIR:"
    echo "    git push origin HEAD"
fi
