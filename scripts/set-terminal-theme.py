#!/usr/bin/env python3
"""
Switch the whole terminal color stack (Ghostty/Macuake, lsd, starship, fzf,
fish) to a single Ghostty theme in one shot, so every tool reads its colors
from the same 16-color palette instead of drifting out of sync.

Usage:
  set-terminal-theme.py <theme-name> [--background HEXRGB] [--font-size N]

<theme-name> must be a file in Muxy's bundled Ghostty theme catalog
(/Applications/Muxy.app/.../ghostty/themes/) or already present in
~/.config/ghostty/themes/.
"""
import argparse
import re
import shutil
import subprocess
from pathlib import Path

HOME = Path.home()
MUXY_THEMES = Path(
    "/Applications/Muxy.app/Contents/Resources/Muxy_Muxy.bundle/ghostty/themes"
)
GHOSTTY_DIR = HOME / ".config/ghostty"
GHOSTTY_THEMES_DIR = GHOSTTY_DIR / "themes"
GHOSTTY_CONFIG = GHOSTTY_DIR / "config"
LSD_COLORS = HOME / ".config/lsd/colors.yaml"
LSD_CONFIG = HOME / ".config/lsd/config.yaml"
STARSHIP_TOML = HOME / ".config/starship.toml"
FISH_CONFIG = HOME / ".config/fish/config.fish"

# Role -> palette index, shared by lsd/starship/fzf so every tool picks the
# same slice of whatever 16-color palette the chosen theme provides.
ROLE_INDEX = {
    "red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6,
    "white": 7, "bright_black": 8, "bright_red": 9, "bright_green": 10,
    "bright_yellow": 11, "bright_blue": 12, "bright_magenta": 13,
    "bright_cyan": 14, "bright_white": 15,
}


def parse_theme(path: Path) -> dict:
    palette = {}
    meta = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        m = re.match(r"palette\s*=\s*(\d+)=#?([0-9a-fA-F]{6})", line)
        if m:
            palette[int(m.group(1))] = m.group(2).lower()
            continue
        m = re.match(r"(background|foreground|cursor-color)\s*=\s*#?([0-9a-fA-F]{6})", line)
        if m:
            meta[m.group(1)] = m.group(2).lower()
    return {"palette": palette, **meta}


def role(theme: dict, name: str) -> str:
    return theme["palette"][ROLE_INDEX[name]]


def hex_to_rgb_sgr(hex_color: str, bold: bool = False) -> str:
    r, g, b = (int(hex_color[i:i + 2], 16) for i in (0, 2, 4))
    prefix = "1;" if bold else ""
    return f"{prefix}38;2;{r};{g};{b}"


def force_lsd_color_always():
    # lsd's "auto" color detection doesn't reliably see Macuake's PTY as
    # color-capable, which silently drops most of colors.yaml.
    if not LSD_CONFIG.exists():
        return
    text = LSD_CONFIG.read_text()
    text = re.sub(
        r'(Possible values: never, auto, always\n\s*when:\s*)\w+',
        r"\g<1>always",
        text,
        count=1,
    )
    LSD_CONFIG.write_text(text)


def find_theme_file(name: str) -> Path:
    local = GHOSTTY_THEMES_DIR / f"{name}.conf"
    if local.exists():
        return local
    bundled = MUXY_THEMES / name
    if bundled.exists():
        GHOSTTY_THEMES_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy(bundled, local)
        return local
    raise SystemExit(f"Theme '{name}' not found in {GHOSTTY_THEMES_DIR} or {MUXY_THEMES}")


def write_ghostty_config(theme_name: str, background: str, font_size: int):
    text = GHOSTTY_CONFIG.read_text() if GHOSTTY_CONFIG.exists() else ""
    text = re.sub(r"^font-size\s*=.*$", f"font-size = {font_size}", text, flags=re.M)
    text = re.sub(r"^theme\s*=.*$", f"theme = {theme_name}", text, flags=re.M)
    if re.search(r"^background\s*=.*$", text, flags=re.M):
        text = re.sub(r"^background\s*=.*$", f"background = {background}", text, flags=re.M)
    else:
        text = text.replace(f"theme = {theme_name}", f"theme = {theme_name}\nbackground = {background}")
    # Near-opaque: at low opacity the true background blends with whatever
    # is behind the window and stops matching the hex you actually asked for.
    text = re.sub(r"^background-opacity\s*=.*$", "background-opacity = 0.95", text, flags=re.M)
    GHOSTTY_CONFIG.write_text(text)


def write_lsd_colors(t: dict):
    LSD_COLORS.write_text(f"""user: "#{role(t,'magenta')}"
group: "#{role(t,'blue')}"
permission:
  read: "#{role(t,'green')}"
  write: "#{role(t,'yellow')}"
  exec: "#{role(t,'red')}"
  exec-sticky: "#{role(t,'magenta')}"
  no-access: "#{role(t,'bright_black')}"
  octal: "#{role(t,'cyan')}"
  acl: "#{role(t,'cyan')}"
  context: "#{role(t,'bright_blue')}"
date:
  hour-old: "#{role(t,'cyan')}"
  day-old: "#{role(t,'bright_blue')}"
  older: "#{role(t,'bright_cyan')}"
size:
  none: "#{role(t,'bright_black')}"
  small: "#{role(t,'green')}"
  medium: "#{role(t,'yellow')}"
  large: "#{role(t,'bright_red')}"
inode:
  valid: "#{role(t,'bright_magenta')}"
  invalid: "#{role(t,'bright_black')}"
links:
  valid: "#{role(t,'bright_magenta')}"
  invalid: "#{role(t,'bright_black')}"
tree-edge: "#{role(t,'white')}"
git-status:
  default: "#{t['foreground']}"
  unmodified: "#{role(t,'bright_black')}"
  ignored: "#{role(t,'bright_black')}"
  new-in-index: "#{role(t,'green')}"
  new-in-workdir: "#{role(t,'green')}"
  typechange: "#{role(t,'yellow')}"
  deleted: "#{role(t,'red')}"
  renamed: "#{role(t,'green')}"
  modified: "#{role(t,'yellow')}"
  conflicted: "#{role(t,'red')}"
""")


def write_starship_palette(t: dict, bg: str):
    palette_block = f"""[palettes.terminal_theme]
rosewater = "#{role(t,'bright_magenta')}"
flamingo = "#{role(t,'bright_magenta')}"
pink = "#{role(t,'bright_magenta')}"
mauve = "#{role(t,'magenta')}"
red = "#{role(t,'red')}"
maroon = "#{role(t,'bright_red')}"
peach = "#{role(t,'yellow')}"
yellow = "#{role(t,'yellow')}"
green = "#{role(t,'green')}"
teal = "#{role(t,'cyan')}"
sky = "#{role(t,'bright_blue')}"
sapphire = "#{role(t,'bright_cyan')}"
blue = "#{role(t,'blue')}"
lavender = "#{role(t,'bright_blue')}"
text = "#{t['foreground']}"
subtext1 = "#{role(t,'bright_black')}"
subtext0 = "#{role(t,'bright_black')}"
overlay2 = "#{role(t,'bright_black')}"
overlay1 = "#{role(t,'white')}"
overlay0 = "#{role(t,'white')}"
surface2 = "#{role(t,'white')}"
surface1 = "#{role(t,'white')}"
surface0 = "#{role(t,'white')}"
base = "#{bg}"
mantle = "#{bg}"
crust = "#{bg}"
"""
    text = STARSHIP_TOML.read_text()
    text = re.sub(r'^palette\s*=\s*".*"$', 'palette = "terminal_theme"', text, count=1, flags=re.M)
    text = re.sub(r"\[palettes\.\w+\]\n(?:.*\n)*?(?=\n\S|\Z)", palette_block, text, count=1)
    STARSHIP_TOML.write_text(text)


def write_fzf_and_fish_colors(t: dict, bg: str):
    fzf_block = f'''# fzf styling (auto-generated by set-terminal-theme.py)
set -gx FZF_DEFAULT_OPTS "
  --color=bg+:#{role(t,'bright_black')},bg:-1,spinner:#{role(t,'magenta')},hl:#{role(t,'red')} \\
  --color=fg:#{t['foreground']},header:#{role(t,'red')},info:#{role(t,'magenta')},pointer:#{role(t,'magenta')} \\
  --color=marker:#{role(t,'blue')},fg+:#{t['foreground']},prompt:#{role(t,'magenta')},hl+:#{role(t,'red')} \\
  --color=selected-bg:#{role(t,'white')} \\
  --color=border:#{role(t,'bright_black')},label:#{t['foreground']},gutter:-1
  --no-border
  --preview-window noborder
  --margin=1
  --padding=2
  --layout=reverse
"'''
    text = FISH_CONFIG.read_text()
    text = re.sub(r"# fzf styling.*?\n\"", fzf_block, text, count=1, flags=re.S)
    fish_color_block = (
        "# BEGIN fish_color (auto-generated by set-terminal-theme.py)\n"
        f"set fish_color_command {role(t,'blue')}\n"
        f"set fish_color_normal {t['foreground']}\n"
        f"set fish_color_autosuggestion {role(t,'bright_black')}\n"
        f"set fish_color_param {t['foreground']}\n"
        f"set fish_color_option {role(t,'yellow')}\n"
        f"set fish_color_quote {role(t,'green')}\n"
        f"set fish_color_redirection {role(t,'cyan')}\n"
        f"set fish_color_end {role(t,'magenta')}\n"
        f"set fish_color_error {role(t,'red')}\n"
        f"set fish_color_comment {role(t,'bright_black')}\n"
        f"set fish_color_operator {role(t,'cyan')}\n"
        f"set fish_color_escape {role(t,'cyan')}\n"
        f"set fish_color_cwd {role(t,'blue')}\n"
        "# END fish_color (auto-generated)"
    )
    if "# BEGIN fish_color (auto-generated" in text:
        text = re.sub(
            r"# BEGIN fish_color \(auto-generated.*?# END fish_color \(auto-generated\)",
            fish_color_block,
            text,
            count=1,
            flags=re.S,
        )
    else:
        text = re.sub(
            r"set fish_color_command .*\nset fish_color_normal .*\nset fish_color_autosuggestion .*",
            fish_color_block,
            text,
            count=1,
        )
    # lsd's own file-type colors, separate from colors.yaml. fi must be an
    # explicit color (not "0"/reset) or lsd falls back to its own near-white
    # default for regular file names, unreadable on a light background.
    ls_colors = (
        f"di={hex_to_rgb_sgr(role(t,'blue'), bold=True)}:"
        f"fi={hex_to_rgb_sgr(t['foreground'])}:"
        f"ln={hex_to_rgb_sgr(role(t,'cyan'), bold=True)}:"
        f"ex={hex_to_rgb_sgr(role(t,'green'), bold=True)}"
    )
    text = re.sub(r'set -gx LS_COLORS ".*"', f'set -gx LS_COLORS "{ls_colors}"', text)
    if "LS_COLORS" not in text:
        text += f'\nset -gx LS_COLORS "{ls_colors}"\n'
    FISH_CONFIG.write_text(text)


def restart_macuake():
    subprocess.run(["pkill", "-x", "Hakuke"], check=False)
    subprocess.run(["open", "-a", "Hakuke"], check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme_name")
    ap.add_argument("--background", default=None, help="override hex background (no #)")
    ap.add_argument("--font-size", type=int, default=15)
    args = ap.parse_args()

    theme_path = find_theme_file(args.theme_name)
    theme = parse_theme(theme_path)
    bg = args.background or theme.get("background", "1e1e1e")

    write_ghostty_config(args.theme_name, bg, args.font_size)
    write_lsd_colors(theme)
    force_lsd_color_always()
    write_starship_palette(theme, bg)
    write_fzf_and_fish_colors(theme, bg)
    restart_macuake()
    print(f"Switched to '{args.theme_name}' (background=#{bg}). Macuake restarted.")


if __name__ == "__main__":
    main()
