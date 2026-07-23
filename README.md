# Hakuke

> **Alpha** — Quake-style drop-down terminal for macOS, powered by [Ghostty](https://ghostty.org). Fork of [menemy/macuake](https://github.com/menemy/macuake).

One hotkey. Instant terminal. `Option+Space` slides it down from the top of any screen.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)

## Features

- **GPU-accelerated** — GhosttyKit Metal renderer. True color, ligatures, GPU text shaping.
- **Hotkey toggle** — `Option+Space` (customizable) from any app. No Dock icon.
- **Tabs & split panes** — multiple sessions with horizontal/vertical splits.
- **Ghostty themes** — use any Ghostty config for fonts, colors, opacity, keybindings.
- **MCP server** — built-in HTTP server (port 19876) with 17 tools. Control from Claude Code, Cursor, or any MCP client.
- **Socket API** — Unix socket at `/tmp/hakuke.sock` for scripting.
- **Multi-display** — follows cursor across screens, notch-aware.

## Install

Download from [Releases](https://github.com/hakanuzum/hakuke/releases), or:

```bash
curl -LO https://github.com/hakanuzum/hakuke/releases/latest/download/Hakuke.dmg
open Hakuke.dmg
# Drag to /Applications
```

The `.dmg` is ad-hoc signed (not notarized) — first launch needs right-click → Open.

## Usage

Launch Hakuke — it lives in the menu bar (no Dock icon). Press `Option+Space` to toggle.

| Shortcut | Action |
|----------|--------|
| `Option+Space` | Toggle terminal |
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab |
| `Cmd+D` | Split horizontal |
| `Cmd+Shift+D` | Split vertical |
| `Cmd+]` / `Cmd+[` | Next / previous pane |
| `Cmd+1`..`9` | Switch to tab N |
| `Cmd+,` | Settings |

## Appearance / theming

This app targets **any shell** (zsh, fish, bash, whatever) and **any prompt setup** —
it should never assume a particular user's dotfiles. Two layers:

1. **The terminal itself** (font, palette, opacity, cursor) is entirely a Ghostty config
   concern: `~/.config/ghostty/config`, and any theme file dropped into
   `~/.config/ghostty/themes/`. Independent of shell choice.
2. **Prompt/tool colors** (`starship`, `lsd`, `fzf`, fish's own `fish_color_*`) are each
   their own separate config with their own hardcoded palette, and *do not* follow the
   terminal's theme automatically — that's the actual bug pattern that kept resurfacing
   during development (terminal switches to a light theme, `lsd`/`starship` keep emitting
   truecolor tuned for a dark one). `scripts/set-terminal-theme.py` is a stopgap: given a
   Ghostty theme name, it derives a consistent role mapping (red/green/blue/etc.) and
   regenerates all of the above from the *same* palette in one shot. It's shell-agnostic
   in principle but currently only writes fish's config — a zsh equivalent, and ideally a
   prompt-tool-agnostic mechanism, is open.
3. **Not yet built:** a real in-app theme picker (Settings → Appearance) that does this
   without a companion script. Settings currently only exposes "Open Config / Reload
   Config" buttons pointing at the raw Ghostty config file — see Known Issues.

```bash
python3 scripts/set-terminal-theme.py "<Ghostty theme name>" [--background HEXRGB] [--font-size N]
```

### Ghostty config

Hakuke uses your Ghostty config (`~/.config/ghostty/config`). Open it from Settings or:

```bash
echo '{"action":"state"}' | nc -U /tmp/hakuke.sock
```

## MCP Server

Add to Claude Code:

```bash
claude mcp add --transport http hakuke http://localhost:19876/mcp
```

17 tools available: `state`, `list`, `toggle`, `show`, `hide`, `pin`, `unpin`, `new_tab`, `focus`, `close_session`, `execute`, `read`, `paste`, `control_char`, `clear`, `split`, `set_appearance`.

## Socket API

See [API.md](API.md) for the full reference.

```bash
# Execute a command
echo '{"action":"execute","command":"ls -la"}' | nc -U /tmp/hakuke.sock

# Read terminal output
echo '{"action":"read","lines":50}' | nc -U /tmp/hakuke.sock
```

## Architecture

```
Hakuke/Sources/Hakuke/
├── API/              # ControlServer (socket API)
├── MCP/              # MCPHTTPServer (MCP over HTTP)
├── Panes/            # PaneManager, PaneNode tree
├── Settings/         # SettingsView, HelpView
├── Tabs/             # TabManager, TabBarView
├── Terminal/         # GhosttyApp, GhosttyBackend, GhosttyTerminalView
├── Updates/          # SparkleUpdater
└── Window/           # WindowController, TerminalPanel, ScreenDetector
```

- **GhosttyKit** — vendored xcframework, GPU Metal terminal engine
- **KeyboardShortcuts** — global hotkey (sindresorhus)
- **SPM** project (not Xcode), `swift build` / `swift test`

## Building from source

Requires: macOS 14+, Swift 5.9+, **Zig 0.15.2 exactly** (hard version-gated at compile
time — 0.16 fails immediately), and a **full Xcode.app install** (Command Line Tools
alone were not enough to get GhosttyKit's Apple-SDK detection working during
development of this fork — a lazy-dependency build step failed to resolve the SDK path
via `xcode-select`/`xcrun` on a CLT-only machine).

```bash
git clone --recursive https://github.com/hakanuzum/hakuke.git
cd hakuke
brew install zig@0.15   # or download 0.15.2 directly from ziglang.org
./scripts/build-ghostty.sh
swift build -c release
```

## Known issues

- **Menu bar / dialog text still says the old name in current releases.** The `.dmg`s
  published so far were produced by patching the *compiled upstream binary* (icon,
  `Info.plist` display name, bundle id) rather than a from-source rebuild, because the
  from-source build was blocked (see above) on the machine used to cut those releases.
  A handful of strings compiled into the binary — permission-prompt dialogs, the
  menu-bar dropdown title, debug window titles — still read the old name until someone
  does a real from-source build and publishes that instead. The source tree itself
  (this repo) has already been fully renamed; it's specifically the *currently
  published `.dmg`* that's a patched binary, not a rebuild.
- **No in-app theme picker yet** (see Appearance above) — external script only.
- Not notarized; Gatekeeper will warn on first launch.

## Attribution / License

MIT — this is a fork of [menemy/macuake](https://github.com/menemy/macuake). See
[LICENSE](LICENSE).
