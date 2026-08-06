#!/usr/bin/env bash
# Refresh vendor/themes from upstream iTerm2-Color-Schemes.
#
# Hakuke ships its own theme catalog so a fresh install has themes without
# depending on Ghostty.app, Homebrew or any other terminal being present.
# Upstream is the canonical source these catalogs are generated from; it is MIT
# licensed and its ghostty/ directory is already in Ghostty's own theme format.
#
# Usage: scripts/fetch-themes.sh

set -euo pipefail

UPSTREAM="https://github.com/mbadolato/iTerm2-Color-Schemes.git"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$PROJECT_ROOT/vendor/themes"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Cloning $UPSTREAM (sparse: ghostty/ only)..."
git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM" "$WORK/upstream" >/dev/null 2>&1
git -C "$WORK/upstream" sparse-checkout set ghostty >/dev/null 2>&1

SHA="$(git -C "$WORK/upstream" rev-parse HEAD)"
COUNT="$(find "$WORK/upstream/ghostty" -type f | wc -l | tr -d ' ')"
echo "==> Upstream $SHA — $COUNT themes"

echo "==> Replacing $DEST..."
rm -rf "$DEST"
mkdir -p "$DEST/themes"
cp -R "$WORK/upstream/ghostty/." "$DEST/themes/"
cp "$WORK/upstream/LICENSE" "$DEST/LICENSE"

cat > "$DEST/README.md" <<EOF
# Bundled theme catalog

Ghostty-format color schemes vendored from
[mbadolato/iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
(MIT — see \`LICENSE\`).

Hakuke ships these so the theme picker works on a clean machine, with no
dependency on Ghostty.app, Homebrew or any other terminal being installed.
User themes in \`~/.config/ghostty/themes\` take precedence over these.

Do not edit by hand — regenerate with \`scripts/fetch-themes.sh\`.

- Upstream commit: \`$SHA\`
- Themes: $COUNT
EOF

echo "==> Wrote $DEST ($(find "$DEST/themes" -type f | wc -l | tr -d ' ') themes)"
