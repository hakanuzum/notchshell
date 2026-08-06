# Bundled terminfo

`xterm-ghostty`, the terminal type libghostty announces via `TERM`.

## Why this is here

libghostty sets `TERM=xterm-ghostty` for every shell it spawns, and no operating
system ships that entry. Unless the app carries it, nothing on the machine can read
it: vim, less, tmux and everything else built on ncurses degrade or refuse to start.

This went unnoticed during development because another Ghostty-based terminal was
installed on the development machine and had leaked `TERMINFO` into the environment.
On a clean machine the terminal would have been broken.

## Provenance

`ghostty.terminfo` is the source Ghostty generates from `src/terminfo/ghostty.zig`.
It is not a checked-in file upstream — it is produced during a Ghostty build — so it
is vendored here rather than downloaded, and the repository is self-contained.

Verified equivalent to the entry shipped by Ghostty 1.3.x: compiling this source and
comparing with `infocmp -1x` against a 1.3.x install differs only in the reconstructed
file path comment.

`scripts/build-install.sh` compiles it with `tic -x` into
`Contents/Resources/terminfo`, a sibling of `Contents/Resources/ghostty` — the layout
libghostty expects when deriving `TERMINFO` from `GHOSTTY_RESOURCES_DIR`.

## Updating

Regenerate from a Ghostty checkout matching the vendored GhosttyKit:

    zig build   # in the ghostty source tree
    find . -name ghostty.terminfo   # under .zig-cache

Then verify before committing:

    tic -x -o /tmp/ti vendor/terminfo/ghostty.terminfo
    TERMINFO=/tmp/ti infocmp xterm-ghostty
