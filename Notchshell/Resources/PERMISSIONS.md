# Permissions

Why the entitlements and usage descriptions are what they are.

The rationale lives here rather than as comments in `notchshell.entitlements`:
codesign's entitlement parser rejects XML comments outright —
`AMFIUnserializeXML: syntax error` — so that file has to stay bare.

## Two mechanisms, often confused

**Usage descriptions (`Info.plist`)** are what produce the prompts a user sees.
macOS attributes a child process's request to the app that spawned it and takes
the prompt text from there. **With no key for that permission the request is
denied outright** — no prompt, no dialog, nothing in the app's log. A script in
the terminal just fails and the reason is nowhere the user can look. That silent
failure is why `PermissionDeclarationTests` pins the list.

A terminal cannot know what will be run in it, so it declares everything a process
might reasonably ask for. The wording says who is really asking — "A process
running in the terminal would like to access your contacts", not "Notchshell would
like to access your contacts". Notchshell does not want your contacts; something
you ran does.

**Entitlements (`notchshell.entitlements`)** — the `com.apple.security.cs.*` keys
only take effect when signing with `--options runtime`, which needs a Developer ID.
Ad-hoc builds ignore them. They are declared now so a signed build behaves like the
one being developed against instead of failing differently the first time it is
notarised.

## Why each entitlement

| Entitlement | Reason |
|---|---|
| `app-sandbox` = false | The app exists to run programs the user chooses, with the user's own access to their own files. A sandbox defeats the purpose. |
| `cs.allow-jit`, `cs.allow-unsigned-executable-memory` | Interpreters with a JIT — node, python, java — allocate executable memory. Under a hardened runtime these are killed without it. |
| `cs.disable-library-validation` | Binaries the user builds and runs are not signed by us. |
| `cs.allow-dyld-environment-variables` | Shells and build tools set `DYLD_*` to inject or relocate libraries; the hardened runtime strips those variables otherwise. |
| `automation.apple-events` | `osascript`, and anything driving another app. Paired with `NSAppleEventsUsageDescription`; one without the other either blocks the call or prompts with no explanation. |
| `network.client`, `network.server` | A process may listen on a socket — a dev server, `ssh -R`, a language server. |

## Not requested, deliberately

**Full Disk Access** cannot be requested; it is granted by the user in System
Settings. It is what a shell needs to read `~/Library/Mail`, another app's
container, or a Time Machine volume. Everything else works without it, so the app
does not nag — it is documented where someone hits the wall instead.

**Accessibility** is for controlling other applications. This app has no reason to,
and asking for it would be a red flag on a terminal.

**Screen Recording** is asked for, but only when the user presses record.

This used to say "not needed, not asked for", and the reasoning behind that still
holds — a terminal that asks to record your screen on launch has no good answer
for why. Asking at the moment the user requests a recording does: the request is
the thing they just asked for, and every other part of the app works without it.
Nothing prompts, nags or degrades until that button is pressed.

There is no `NSUsageDescription` key for this one — macOS writes the prompt text
itself — so unlike the keys above there is nothing here to get wrong, and nothing
to explain ourselves with either. That is a second reason the timing has to carry
the explanation. The request goes through `CGRequestScreenCaptureAccess`.

A first grant does not reach the running process: macOS hands screen capture to an
app at launch, so a user who grants it mid-session is still denied until they
relaunch. `PanelRecorder` reports that case separately rather than leaving a record
button that silently does nothing.

## Ad-hoc signing loses grants on every rebuild

TCC keys its grants on the code signature. An ad-hoc build gets a fresh signature
each time it is built, so every permission the user granted is forgotten and asked
again. This is a property of unsigned development builds, not a bug to fix — but it
does mean permission behaviour cannot be judged from a dev build. A Developer
ID-signed, notarised build keeps its grants across updates.
