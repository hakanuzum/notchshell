# Hakuke

Quake-style drop-down terminal for macOS. Fork of [menemy/macuake](https://github.com/menemy/macuake) (Ghostty-powered), rebranded and extended with a one-command theme switcher that keeps the terminal app, `lsd`, `starship`, `fzf` and `fish` all on the same color palette.

## Status

- `source/` — the forked Swift source (MIT, same as upstream). Building `GhosttyKit.xcframework` requires **Zig 0.15.2 exactly** and currently only builds reliably on a machine with a full Xcode.app install (not just Command Line Tools) — see `source/scripts/build-ghostty.sh`.
- The current `.dmg` releases were produced by patching the compiled upstream binary (icon, `Info.plist` display name/bundle id) rather than a from-source rebuild, since the local build environment used so far only had Command Line Tools. A couple of strings baked into the compiled binary (permission dialogs, the menu-bar dropdown title) still read "macuake" until someone does a real from-source build.
- Everything *outside* the compiled binary — theme, fonts, colors, shell integration — is fully rebrandable and covered by `scripts/set-terminal-theme.py`.

## Theme switching

```bash
python3 scripts/set-terminal-theme.py "<Ghostty theme name>" [--background HEXRGB] [--font-size N]
```

Pulls the named theme's 16-color palette and regenerates, in one shot:

- `~/.config/ghostty/config` (theme + font size)
- `~/.config/lsd/colors.yaml` and `~/.config/lsd/config.yaml` (`color.when: always` — lsd's `auto` detection doesn't reliably see this app's PTY as color-capable)
- `~/.config/starship.toml` palette
- `~/.config/fish/config.fish` (`fish_color_*`, `FZF_DEFAULT_OPTS`, `LS_COLORS`)

Then restarts the app. The theme file must already exist as `~/.config/ghostty/themes/<name>.conf`, or be reachable via `vendor/ghostty`'s own bundled theme catalog once the submodule is checked out.

## Layout

```
source/      forked Swift app (MaQuake/), builds Hakuke.app
dotfiles/    reference config this repo's theme switcher generates into ~/.config
scripts/     set-terminal-theme.py
assets/      icon source (Bilake mountain mark) + built .icns
```

## Building from source

```bash
git clone --recursive https://github.com/hakanuzum/hakuke.git
cd hakuke/source
brew install zig@0.15   # must be 0.15.2, hard version-gated at compile time
./scripts/build-ghostty.sh
swift build -c release
```

Needs a full Xcode.app (not just Command Line Tools) for reliable Apple SDK detection during the GhosttyKit build.
