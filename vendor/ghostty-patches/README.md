# Patches applied to the Ghostty submodule

Applied by `scripts/build-ghostty.sh` before building and reverted afterwards, so
`vendor/ghostty` stays a clean checkout of the pinned tag.

## 0001 — only build iOS slices for the universal target

Ghostty's xcframework step constructs the iOS and iOS-Simulator build graphs
unconditionally, then discards them unless the target is `universal`:

    const ios = try GhosttyLib.initStatic(b, ...);        // always
    ...
    .libraries = switch (target) {
        .universal => &.{ macos_universal, ios, ios_sim },
        .native    => &.{ macos_native },                 // iOS unused
    }

Constructing that graph resolves the iOS SDK, so a macOS-only build fails on any
machine without Xcode's iOS platform:

    xcrun: error: SDK "iphoneos" cannot be located

This is a desktop app for macOS. It has no iOS target and never links those
slices, so the patch makes all three unused libraries conditional on the target
that actually uses them. Beyond unblocking the build it removes a universal macOS
library and two iOS libraries from every native build.

Worth proposing upstream — nothing about it is specific to this project.

## Re-verify on upgrade

The patch is against a pinned tag. After bumping the submodule:

    cd vendor/ghostty && git apply --check ../ghostty-patches/0001-*.patch

If it no longer applies, check whether upstream fixed it before rewriting it.

## 0002 — iTerm2 inline images (OSC 1337 File=)

Ghostty parses OSC 1337 and implements `CurrentDir`; every other key, `File` among
them, lands in an "unimplemented" branch that logs and returns invalid. So an image
sent the iTerm2 way — which is what `imgcat` and a good deal of tooling still speaks —
draws nothing.

The patch does not add a second image path. The two protocols disagree only about how
an image is announced; decode, store, place at the cursor and move the cursor past it
are the same job, and Ghostty already does all of it for the Kitty graphics protocol,
with a renderer behind it. So `File=` is parsed into a command and translated into a
Kitty `transmit_and_display`, and the existing machinery draws it.

PNG is passed through untouched, since Kitty's transmission format has a PNG variant
and the decode happens downstream. JPEG has no place in that format, so it is decoded
with wuffs — already vendored for the PNG path — and handed over as raw RGBA. Anything
else is dropped rather than guessed at. `inline=1` is required, because without it
iTerm2 downloads the file instead, and `width`/`height` are honoured only in their
plain-number (cell) form; `Npx`, `%` and `auto` resolve to the image's natural size.

Three things about this codebase that the patch had to learn the hard way, each of
which is a compile error rather than a bug:

- `osc.Command` is `union(Key)` and `stream.Action` is `union(Key)` too, where `Key` is
  a `LibEnum` whose name order is a C ABI contract. A new variant has to be appended to
  *both* the union and the name list, in the same position. Filing it next to related
  code renumbers the ABI.
- `Parser.reset` switches over every command variant to decide what to free. A new one
  has to be named there even when it owns nothing.
- `kitty.graphics` re-exports `Command`, `Image` and `Response` but not `Transmission`,
  which a caller building a command by hand needs. The patch exports it.

If Ghostty implements `File=` upstream this patch stops applying, which is the intended
signal: delete it and take theirs.
