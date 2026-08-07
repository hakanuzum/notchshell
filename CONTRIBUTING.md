# Contributing to Notchshell

Thanks for taking the time. This is a small project with a deliberate style; the notes
below are what keeps it coherent.

## Building

```bash
brew install zig@0.15            # Zig 0.15.2 exactly; 0.16 fails immediately
./scripts/build-ghostty.sh       # libghostty from vendor/ghostty (slow, once)
./scripts/build-install.sh       # build, sign ad-hoc, install to /Applications
./scripts/run-tests.sh           # every suite
```

A full Xcode install is required (not just Command Line Tools) — Swift macro plugins and
`xcrun metal` do not exist under CLT.

## Commits

The history is meant to be read. Match it:

- **Subject** in the imperative, one line, no trailing period: *"Zoom the font with
  ⌘-scroll and pinch"*, not *"Added font zoom"*.
- **Body** explains the *why*, not the *what* — the diff already shows what changed.
  When a decision was measured rather than guessed, record the measurement.
- One logical change per commit. If the subject needs an "and", it is probably two.
- No AI/tool trailers, no attribution footers.

## Pull requests

- Branch from `main`; keep the PR to one coherent change.
- Run `./scripts/run-tests.sh`. The baseline is **80 pass, 13 fail, 2 skipped** — the 13
  are environmental (they need a real window server or an initialised Ghostty) and fail
  identically before and after any change. Compare against that number, not zero. A new
  failure outside the 13 is a regression.
- Do not bump the version or touch release assets in a feature PR — releasing is its own
  step (below).
- Nothing personal or machine-specific in the diff: no signing identities, absolute home
  paths, usernames, or IPs. The repo is public.
- Respect the two hard boundaries: **never write the user's Ghostty config** (settings go
  to `~/.config/notchshell/overrides.conf`) and **never write shell configuration**.

## Versioning

`MAJOR.MINOR.PATCH`, pre-1.0:

- **PATCH** (`0.3.3 → 0.3.4`) — bug fixes, small self-contained features.
- **MINOR** (`0.3.x → 0.4.0`) — notable features or behaviour changes.
- **MAJOR** — reserved for 1.0 and beyond.

`CFBundleShortVersionString` is the marketing version; `CFBundleVersion` is a
monotonic integer Sparkle compares.

## Releasing

Auto-update is wired through Sparkle and must stay working. Every release:

1. `./scripts/bump-version.sh <major|minor|patch>` — moves both version keys in
   `Info.plist` together; commit as `Release <version>`.
2. `./scripts/build-install.sh`
3. `./scripts/make-dmg.sh`
4. `./scripts/make-appcast.sh <version>` — signs the DMG with the EdDSA key and writes
   `build/appcast/appcast.xml`.
5. `gh release create v<version> build/Notchshell-<version>.dmg build/appcast/appcast.xml`
   on **both** remotes.

`appcast.xml` is a **required** release asset — the app fetches it from
`releases/latest/download/appcast.xml` to discover and verify updates. The `Source code`
archives GitHub attaches automatically are not ours and are left alone.

Changing the Sparkle signing key breaks auto-update for every already-shipped build (they
can no longer verify new signatures) — do not regenerate it without intending exactly
that.

### Release notes

Group the notes under the headings below, in this order, omitting any that are empty.
It is [Keep a Changelog](https://keepachangelog.com) trimmed to what this app ships.
Write for someone deciding whether to update, one bullet per user-visible change,
imperative and plain — not commit subjects.

- **Added** — new capabilities.
- **Changed** — behaviour or appearance of something that already existed.
- **Fixed** — bugs resolved.
- **Removed** — things taken out.

Below those, keep the standing **Install / update** footer: on the current version or
later, Settings installs updates in place; a fresh install is the DMG with a
first-launch right-click → Open; macOS 14+, Apple silicon. When a release cannot
auto-update from older ones (a signing-key change), say so under **Changed** with the
one-time manual-install note.

## Reporting bugs

Open an issue with your macOS version, the Notchshell version (menu bar → the version
line, or Settings), and the steps to reproduce. The templates prompt for these.
