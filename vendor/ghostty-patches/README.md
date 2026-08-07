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
