<div align="center">

<img src="docs/media/logo.png" width="112" alt="">

# Notchshell

**One hotkey. The terminal is already open.**

A native drop-down terminal for macOS — Swift and AppKit, no Electron, no web view.
Press `⌥ Space` anywhere and it slides down over whatever you were doing; press it
again and it is gone. The terminal itself is [Ghostty](https://ghostty.org) —
GPU-rendered on Metal, true colour, ligatures.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)
![Ghostty 1.3.1](https://img.shields.io/badge/Ghostty-1.3.1-00F888?logoColor=white)
![License: personal, non-commercial](https://img.shields.io/badge/License-personal%2C%20non--commercial-red)

<img src="docs/media/demo.gif" width="820" alt="Notchshell dropping down, splitting panes, switching themes and going translucent">

</div>

---

## Install

Download the latest `.dmg` from [**Releases**](https://github.com/hakanuzum/notchshell/releases/latest),
open it, and drag the app onto Applications.

<div align="center">
<img src="docs/media/installer.png" width="560" alt="The installer window: drag Notchshell onto Applications">
</div>

The build is signed ad-hoc rather than notarized, so Gatekeeper stops the first
launch. Right-click the app in `/Applications` and choose **Open** once; after that it
opens normally.

Notchshell lives in the menu bar and has no Dock icon. Press `⌥ Space` to drop it.

## The tour

Everything below, in one take — [**watch the full tour**](docs/media/tour.mp4) (33s).

https://github.com/hakanuzum/notchshell/raw/main/docs/media/tour.mp4

### Tabs and split panes

`⌘ D` splits horizontally, `⌘ ⇧ D` vertically, and every pane is a real shell. Tabs sit
on a strip the height of the menu bar, so the terminal keeps the space.

![Split panes running a git graph and a syntax-highlighted file](docs/media/panes.png)

### 602 themes, applied live

The theme picker ships the whole [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
catalog, so it works on a clean machine with nothing else installed. Pick one and the
running panes repaint — no restart, no reload.

![The theme picker open over a light theme](docs/media/themes.png)

Themes in `~/.config/ghostty/themes` take precedence over the bundled ones, and a
`light:A,dark:B` pair follows the system appearance.

### Opacity, font size and height, on the tab bar

The three things people actually reach for are one click away, not buried in Settings.
Drag the handle on the bottom edge to resize the panel.

![The panel translucent, the desktop showing through](docs/media/opacity.png)

### Record what you did

The camera button records the active tab to MP4 in `~/Movies/Notchshell`, and can export
a GIF from it afterwards. Only the terminal is in frame — not the chrome, not the tab
bar, not what is behind the panel.

## Shortcuts

| | |
|---|---|
| Toggle terminal | `⌥ Space` |
| Pin / unpin | `⌘ ⇧ P` |
| New tab · close tab | `⌘ T` · `⌘ W` |
| Reopen closed tab | `⌘ ⇧ T` |
| Next / previous tab | `⌘ ⇧ ]` · `⌘ ⇧ [` |
| Go to tab 1–9 | `⌘ 1` – `⌘ 9` |
| Split horizontal · vertical | `⌘ D` · `⌘ ⇧ D` |
| Next / previous pane | `⌘ ]` · `⌘ [` |
| Copy · paste | `⌘ C` · `⌘ V` |
| Clear screen · find | `⌘ K` · `⌘ F` |
| Settings · Help | `⌘ ,` · `⌘ /` |

Unpinned, the panel hides when it loses focus. Pin it to keep it down.

## Configuration

Notchshell reads your own Ghostty config at `~/.config/ghostty/config` and **never
writes to it**. Anything you change in the app lands in
`~/.config/notchshell/overrides.conf`, which your config is included into — so font,
palette, keybindings and opacity all come from one place you control.

## Automation

Three ways in, all off or ask-first by default.

**Command line.** Settings links `notchshell` onto your `PATH`:

```bash
notchshell              # drop the terminal
notchshell ~/src/app    # drop it with a new tab there
```

**Socket API.** A Unix socket at `/tmp/notchshell.sock`, JSON in and JSON out. See
[API.md](API.md) for every action.

```bash
echo '{"action":"state"}'                      | nc -U /tmp/notchshell.sock
echo '{"action":"execute","command":"ls -la"}' | nc -U /tmp/notchshell.sock
echo '{"action":"read","lines":50}'            | nc -U /tmp/notchshell.sock
```

**MCP.** An HTTP server on port 19876 exposing 18 tools, so an agent can drive the
terminal directly:

```bash
claude mcp add --transport http notchshell http://localhost:19876/mcp
```

The MCP server and the socket API are **disabled until you turn them on** in Settings.
Nothing phones home; there is no telemetry.

## Open from elsewhere

macOS has no "default terminal" setting, so Notchshell answers four routes separately:
Finder's *Services → New Notchshell Tab Here*, `open -a Notchshell <path>` and Open
With, the `notchshell://` URL scheme, and the CLI. Help (`⌘ /`) lists them.

## Build from source

Requires macOS 14+, a full Xcode install (not just Command Line Tools) and
**Zig 0.15.2 exactly** — libghostty is version-gated and 0.16 fails immediately.

```bash
git clone --recursive https://github.com/hakanuzum/notchshell.git
cd notchshell
brew install zig@0.15
./scripts/build-ghostty.sh     # libghostty from vendor/ghostty (slow, once)
./scripts/build-install.sh     # build, sign, install to /Applications
./scripts/make-dmg.sh          # package the installer
./scripts/run-tests.sh         # every suite
```

## License

© 2026 Hakan Uzum. All rights reserved. The source is public to read, and the app is
free for personal, non-commercial use — but **commercial use and redistribution are not
permitted**. See [LICENSE](LICENSE) for the exact terms.

Bundled third-party components keep their own licenses: the terminal engine
[Ghostty](https://ghostty.org) (MIT) and the theme catalog
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) (MIT). Their
notices are reproduced in [LICENSE](LICENSE).
