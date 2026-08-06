#!/usr/bin/env bash
set -euo pipefail

# Download pre-built GhosttyKit.xcframework from GitHub Releases.
# Falls back to building from source if no release is found.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"
XCFRAMEWORK_DIR="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"

if [ -d "$XCFRAMEWORK_DIR" ]; then
    echo "GhosttyKit.xcframework already exists, skipping download"
    exit 0
fi

SHA=$(cd "$GHOSTTY_DIR" && git rev-parse HEAD)
TAG="ghosttykit-$SHA"
REPO="${GITHUB_REPOSITORY:-hakanuzum/notchshell}"

echo "Looking for pre-built GhosttyKit (SHA: ${SHA:0:12})..."

TARBALL="/tmp/GhosttyKit.xcframework.tar.gz"

if gh release download "$TAG" --repo "$REPO" --pattern "GhosttyKit.xcframework.tar.gz" --dir /tmp --clobber 2>/dev/null; then
    echo "Downloaded from release $TAG"
    mkdir -p "$GHOSTTY_DIR/macos"
    tar xzf "$TARBALL" -C "$GHOSTTY_DIR/macos"
    rm -f "$TARBALL"
    echo "Extracted to $XCFRAMEWORK_DIR"
else
    echo "No pre-built release found for $TAG"
    echo "Falling back to building from source..."
    echo "Installing zig@0.15 (Ghostty requires 0.15.x)..."
    brew install zig@0.15 2>/dev/null || true
    export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
    "$SCRIPT_DIR/build-ghostty.sh"
fi
