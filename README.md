<div align="center">

<img src="docs/media/logo.png" width="112" alt="">

# Notchshell

**One hotkey. The terminal is already open.**

Press `⌥ Space` anywhere and it slides down over whatever you were doing.
Press it again and it is gone.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)
![Ghostty 1.3.1](https://img.shields.io/badge/Ghostty-1.3.1-00F888?logoColor=white)
![License: personal, non-commercial](https://img.shields.io/badge/License-personal%2C%20non--commercial-red)

<img src="docs/media/demo.gif" width="820" alt="Notchshell dropping down, splitting panes, switching themes and going translucent">

[**Download**](https://github.com/hakanuzum/notchshell/releases/latest) ·
[Watch the tour](docs/media/tour.mp4) (33s)

</div>

---

## Install

Download the latest `.dmg` from [**Releases**](https://github.com/hakanuzum/notchshell/releases/latest),
open it, and drag the app onto Applications.

<div align="center">
<img src="docs/media/installer.png" width="560" alt="The installer window: drag Notchshell onto Applications">
</div>

The build is signed ad-hoc rather than notarized, so Gatekeeper stops the first launch.
Right-click the app in `/Applications` and choose **Open** once; after that it opens
normally. Notchshell lives in the menu bar and has no Dock icon.

---

## It knows which agent is waiting for you

Run `claude`, `codex`, `gemini` or a dozen others and the tab wears that tool's mark.
When one finishes — or stops to ask you something — while the panel is down, it says so:
a notification you can click to land in the right tab, and a dot that stays until you
look.

Come back to a folder you have worked in before and the mark is still there, faded. One
click picks the conversation back up where you left it.

## Everything it does, one keystroke away

`⌘ P` opens a search box over the terminal: every command, every one of the 602 themes,
by name.

## Tabs and split panes

`⌘ D` splits right, `⌘ ⇧ D` splits down, and every pane is a real shell. `⌘ ⇧ Enter`
blows one pane up to fill the tab and back again. Tabs sit on a strip the height of the
menu bar, so the terminal keeps the space.

![Split panes running a git graph and a syntax-highlighted file](docs/media/panes.png)

Quit with three tabs and a split, and that is what comes back — the shape, the
proportions, and each pane in its own folder.

## 602 themes, applied live

The whole [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
catalog ships with the app, so it works on a clean machine with nothing else installed.
Pick one and the running panes repaint — no restart, no reload.

![The theme picker open over a light theme](docs/media/themes.png)

## Opacity, font size and height, on the tab bar

The three things people actually reach for are one click away, not buried in Settings.
Drag the handle on the bottom edge to resize the panel.

![The panel translucent, the desktop showing through](docs/media/opacity.png)

## Record what you did

The camera button records the active tab to MP4 in `~/Movies/Notchshell`, and can export
a GIF from it afterwards. Only the terminal is in frame — not the chrome, not the tab
bar, not what is behind the panel.

## Open it where you already are

```bash
notchshell .            # a tab in this folder, the way code . or zed . works
notchshell ~/src/app    # or any other
notchshell              # just drop the terminal
```

macOS has no "default terminal" setting, so Notchshell answers the other routes too:
Finder's *Services → New Notchshell Tab Here*, `open -a Notchshell <path>`, and the
`notchshell://` URL scheme. In VS Code, point `"terminal.external.osxExec"` at
`Notchshell.app` and *Open in External Terminal* lands here. Help (`⌘ /`) lists them all.

## Shortcuts

| | | | |
|---|---|---|---|
| Toggle terminal | `⌥ Space` | Split right · down | `⌘ D` · `⌘ ⇧ D` |
| Pin / unpin | `⌘ ⇧ P` | Next / previous pane | `⌘ ]` · `⌘ [` |
| New tab · close | `⌘ T` · `⌘ W` | Zoom pane | `⌘ ⇧ Enter` |
| Reopen closed tab | `⌘ ⇧ T` | Copy · paste | `⌘ C` · `⌘ V` |
| Next / previous tab | `⌘ ⇧ ]` · `⌘ ⇧ [` | Clear screen · find | `⌘ K` · `⌘ F` |
| Go to tab 1–9 | `⌘ 1` – `⌘ 9` | Command palette | `⌘ P` |
| Rename tab | double-click | Settings · Help | `⌘ ,` · `⌘ /` |

Unpinned, the panel hides when it loses focus — pin it to keep it down. Every shortcut
above except `⌘ 1`–`⌘ 9`, `⌃ ⇥` and `⌘ /` can be changed in Settings.

---

<details>
<summary><b>Under the hood</b></summary>

<br>

Swift and AppKit — no Electron, no web view. The terminal itself is
[Ghostty](https://ghostty.org), GPU-rendered on Metal, with true colour and ligatures.

**Your config stays yours.** Notchshell reads `~/.config/ghostty/config` and **never
writes to it**. Anything you change in the app lands in
`~/.config/notchshell/overrides.conf`, which your config is included into. It does not
write your shell configuration either.

**Automation**, all off or ask-first by default, and nothing phones home:

```bash
# Unix socket — JSON in, JSON out. See API.md for every action.
echo '{"action":"state"}' | nc -U /tmp/notchshell.sock

# MCP — an HTTP server exposing 18 tools, so an agent can drive the terminal
claude mcp add --transport http notchshell http://localhost:19876/mcp
```

**Build from source.** Needs macOS 14+, a full Xcode install (not just Command Line
Tools) and **Zig 0.15.2 exactly** — libghostty is version-gated and 0.16 fails
immediately.

```bash
git clone --recursive https://github.com/hakanuzum/notchshell.git
cd notchshell && brew install zig@0.15
./scripts/build-ghostty.sh     # libghostty from vendor/ghostty (slow, once)
./scripts/build-install.sh     # build, sign, install to /Applications
./scripts/run-tests.sh         # every suite
```

</details>

## License and credits

© 2026 Hakan Uzum. The source is public to read and the app is free for personal,
non-commercial use — but **commercial use and redistribution are not permitted**. See
[LICENSE](LICENSE) for the exact terms.

Notchshell began as a fork of [macuake](https://github.com/menemy/macuake) by menemy
(MIT), and owes it the shape of the thing. It stands on
[Ghostty](https://ghostty.org) (MIT) for the terminal,
[iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes) (MIT) for the
themes, and [Sparkle](https://sparkle-project.org) for updates. Their notices are
reproduced in [LICENSE](LICENSE).
