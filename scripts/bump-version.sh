#!/usr/bin/env bash
set -euo pipefail

# Bump the app version in Info.plist consistently.
#
# Usage: ./scripts/bump-version.sh <major|minor|patch|X.Y.Z>
#
#   patch   0.3.4 → 0.3.5   bug fixes, small self-contained features
#   minor   0.3.4 → 0.4.0   notable features or behaviour changes
#   major   0.3.4 → 1.0.0   reserved for 1.0 and beyond
#   X.Y.Z   set exactly
#
# CFBundleShortVersionString is the marketing version people see; CFBundleVersion is a
# monotonic integer Sparkle compares to decide "newer". Both are moved together — a
# marketing bump with a stale build number is a release the updater will not offer.
# This only edits Info.plist; it does not commit, build, or tag. Follow it with the
# release steps in CONTRIBUTING.md.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$PROJECT_ROOT/Notchshell/Resources/Info.plist"
BUDDY=/usr/libexec/PlistBuddy

arg="${1:?usage: bump-version.sh <major|minor|patch|X.Y.Z>}"

current="$($BUDDY -c 'Print :CFBundleShortVersionString' "$PLIST")"
build="$($BUDDY -c 'Print :CFBundleVersion' "$PLIST")"

IFS=. read -r major minor patch <<<"$current"
: "${major:=0}" "${minor:=0}" "${patch:=0}"

case "$arg" in
    major) new="$((major + 1)).0.0" ;;
    minor) new="${major}.$((minor + 1)).0" ;;
    patch) new="${major}.${minor}.$((patch + 1))" ;;
    [0-9]*.[0-9]*.[0-9]*) new="$arg" ;;
    *) echo "unknown bump: $arg (want major|minor|patch|X.Y.Z)" >&2; exit 2 ;;
esac

# CFBundleVersion must only ever climb, whatever the marketing version does.
new_build="$((build + 1))"

$BUDDY -c "Set :CFBundleShortVersionString $new" "$PLIST"
$BUDDY -c "Set :CFBundleVersion $new_build" "$PLIST"

echo "version : $current → $new"
echo "build   : $build → $new_build"
echo
echo "Next (see CONTRIBUTING.md):"
echo "    git commit -am \"Release $new\""
echo "    ./scripts/build-install.sh && ./scripts/make-dmg.sh && ./scripts/make-appcast.sh $new"
echo "    gh release create v$new build/Notchshell-$new.dmg build/appcast/appcast.xml --repo <remote>/notchshell"
