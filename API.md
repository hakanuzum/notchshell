# Notchshell Control API

Unix domain socket server at `/tmp/notchshell.sock`. Send JSON, receive JSON.

## Protocol

Connect to the socket, send a single JSON object with an `"action"` field, read the response. Each response has `"ok": true/false`. On error: `"error": "message"`.

```bash
echo '{"action":"state"}' | nc -U /tmp/notchshell.sock
```

## Actions

### Window Control

| Action | Description | Params | Response |
|--------|-------------|--------|----------|
| `toggle` | Toggle show/hide | — | `{"ok":true}` |
| `show` | Show terminal | — | `{"ok":true}` |
| `hide` | Hide terminal | — | `{"ok":true}` |
| `pin` | Pin (stay visible) | — | `{"ok":true}` |
| `unpin` | Unpin (auto-hide) | — | `{"ok":true}` |

### State

#### `state`

Returns current window state.

```json
{"action":"state"}
```

Response:

```json
{
  "ok": true,
  "visible": true,
  "pinned": false,
  "tab_count": 2,
  "active_tab_index": 0,
  "active_session_id": "UUID",
  "width_percent": 75,
  "height_percent": 50
}
```

#### `list`

Returns all tabs.

```json
{"action":"list"}
```

Response:

```json
{
  "ok": true,
  "count": 2,
  "tabs": [
    {
      "session_id": "UUID",
      "index": 0,
      "title": "zsh",
      "active": true,
      "cwd": "/Users/user"
    }
  ]
}
```

### Tab Management

#### `new-tab`

Create a new terminal tab. Optionally specify starting directory.

```json
{"action":"new-tab"}
{"action":"new-tab", "directory":"/tmp"}
```

Response: `{"ok":true, "session_id":"UUID"}`

#### `focus`

Switch to a tab by session ID or index.

```json
{"action":"focus", "session_id":"UUID"}
{"action":"focus", "index": 1}
```

#### `close-session`

Close a tab. If no `session_id`, closes the active tab.

```json
{"action":"close-session"}
{"action":"close-session", "session_id":"UUID"}
```

### Terminal I/O

All I/O actions target the active tab by default. Pass `"session_id"` to target a specific tab.

#### `execute`

Send a command (appends `\n`).

```json
{"action":"execute", "command":"ls -la"}
{"action":"execute", "command":"ls", "session_id":"UUID"}
```

#### `paste`

Send raw text (no newline appended). Useful for multi-line content.

```json
{"action":"paste", "text":"hello world"}
```

#### `read`

Read terminal screen content. Returns last N lines (default 20).

```json
{"action":"read"}
{"action":"read", "lines": 50}
{"action":"read", "session_id":"UUID"}
```

Response:

```json
{
  "ok": true,
  "session_id": "UUID",
  "lines": ["$ ls", "file1  file2"],
  "rows": 24,
  "cols": 80
}
```

#### `control-char`

Send a control character or special key.

```json
{"action":"control-char", "key":"c"}
```

Supported keys: `c` (Ctrl+C), `d` (Ctrl+D), `z` (Ctrl+Z), `a`, `e`, `k`, `l`, `u`, `w`, `enter`, `esc`, `tab`.

## Errors

```json
{"ok":false, "error":"session not found"}
{"ok":false, "error":"not a terminal tab"}
{"ok":false, "error":"missing command"}
{"ok":false, "error":"unknown action: foo"}
```
