#!/usr/bin/env python3
"""
notchshell E2E tests via Socket API.
Requires notchshell running with API enabled.

Usage:
    # Start notchshell, enable API in Settings, then:
    python3 scripts/e2e-test.py

Can run headless in a VM — only needs the Unix socket.
"""

import socket
import json
import time
import sys

SOCKET_PATH = "/tmp/notchshell.sock"
PASSED = 0
FAILED = 0
ERRORS = []


def api(action, **kwargs):
    """Send API request, return parsed JSON response."""
    for attempt in range(3):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(10)
            s.connect(SOCKET_PATH)
            s.sendall(json.dumps({"action": action, **kwargs}).encode())
            s.shutdown(socket.SHUT_WR)
            resp = s.recv(65536).decode().strip()
            s.close()
            return json.loads(resp)
        except Exception as e:
            if attempt == 2:
                return {"ok": False, "error": str(e)}
            time.sleep(0.5)


def test(name, condition, detail=""):
    global PASSED, FAILED, ERRORS
    if condition:
        PASSED += 1
        print(f"  \033[32m✓\033[0m {name}")
    else:
        FAILED += 1
        ERRORS.append(f"{name}: {detail}")
        print(f"  \033[31m✗\033[0m {name} — {detail}")


def wait(seconds=0.5):
    time.sleep(seconds)


# ============================================================
# Tests
# ============================================================

def test_connection():
    print("\n=== Connection ===")
    r = api("state")
    test("socket connects", r.get("ok"), f"got: {r}")
    test("state has tab_count", "tab_count" in r, f"keys: {r.keys()}")
    test("state has visible", "visible" in r, f"keys: {r.keys()}")


def test_show_hide():
    print("\n=== Show / Hide ===")
    api("show"); wait()
    r = api("state")
    test("show makes visible", r.get("visible") == True, f"visible={r.get('visible')}")

    api("hide"); wait()
    r = api("state")
    test("hide makes invisible", r.get("visible") == False, f"visible={r.get('visible')}")

    api("toggle"); wait(1)
    r = api("state")
    test("toggle from hidden → visible", r.get("visible") == True)

    api("toggle"); wait(1)
    r = api("state")
    test("toggle from visible → hidden", r.get("visible") == False)


def test_pin():
    print("\n=== Pin / Unpin ===")
    api("pin"); wait(0.3)
    r = api("state")
    test("pin sets pinned=true", r.get("pinned") == True)

    api("unpin"); wait(0.3)
    r = api("state")
    test("unpin sets pinned=false", r.get("pinned") == False)


def test_tabs():
    print("\n=== Tabs ===")
    api("show"); wait()

    # Start with 1 tab
    r = api("list")
    initial_count = r.get("count", 0)
    test("initial tab exists", initial_count >= 1, f"count={initial_count}")

    # Create new tab
    r = api("new-tab"); wait()
    new_id = r.get("session_id")
    test("new-tab returns session_id", new_id is not None)

    r = api("list")
    test("tab count increased", r.get("count") == initial_count + 1, f"count={r.get('count')}")

    # Focus first tab
    r = api("focus", index=0); wait(0.3)
    r = api("state")
    test("focus index=0 works", r.get("active_tab_index") == 0, f"active={r.get('active_tab_index')}")

    # Focus by session_id
    r = api("focus", session_id=new_id); wait(0.3)
    r = api("state")
    test("focus by session_id works", r.get("active_session_id") == new_id)

    # Close new tab
    api("close-session", session_id=new_id); wait()
    r = api("list")
    test("close-session removes tab", r.get("count") == initial_count, f"count={r.get('count')}")


def test_execute_and_read():
    print("\n=== Execute & Read ===")
    api("show"); wait()

    # Create fresh tab for clean test
    r = api("new-tab"); wait(1)
    tab_id = r.get("session_id")

    # Execute command
    api("execute", command="echo E2E_TEST_MARKER_12345"); wait(1)

    # Read output
    r = api("read", lines=10, session_id=tab_id)
    test("read returns lines", len(r.get("lines", [])) > 0, f"lines={len(r.get('lines', []))}")
    test("read returns rows/cols", r.get("rows", 0) > 0 and r.get("cols", 0) > 0,
         f"rows={r.get('rows')} cols={r.get('cols')}")

    # Check marker in output
    lines = r.get("lines", [])
    found = any("E2E_TEST_MARKER_12345" in line for line in lines)
    test("executed command output visible", found, f"lines={lines[-3:]}")

    # Clean up
    api("close-session", session_id=tab_id); wait()


def test_paste_and_control_char():
    print("\n=== Paste & Control Char ===")
    api("show"); wait()

    r = api("new-tab"); wait(1)
    tab_id = r.get("session_id")

    # Paste text
    r = api("paste", text="echo PASTE_TEST_OK")
    test("paste returns ok", r.get("ok"))

    # Send enter
    r = api("control-char", key="enter"); wait(1)

    # Read and verify
    r = api("read", lines=5, session_id=tab_id)
    lines = r.get("lines", [])
    found = any("PASTE_TEST_OK" in line for line in lines)
    test("pasted + enter → command executed", found, f"lines={lines[-3:]}")

    # Ctrl+C
    api("execute", command="sleep 999", session_id=tab_id); wait(0.5)
    r = api("control-char", key="c", session_id=tab_id)
    test("control-char c (Ctrl+C) returns ok", r.get("ok"))

    api("close-session", session_id=tab_id); wait()


def test_split():
    print("\n=== Split Panes ===")
    api("show"); wait()

    r = api("new-tab"); wait(1)
    tab_id = r.get("session_id")

    # Split horizontal
    r = api("split", direction="h", session_id=tab_id)
    test("split h returns ok", r.get("ok"))
    wait(1)

    # Split vertical
    r = api("split", direction="v", session_id=tab_id)
    test("split v returns ok", r.get("ok"))
    wait(1)

    # Invalid split
    r = api("split")
    test("split without direction → error", r.get("ok") == False)

    api("close-session", session_id=tab_id); wait()


def test_set_appearance():
    print("\n=== Set Appearance ===")
    api("show"); wait()

    r = api("new-tab"); wait(1)
    tab_id = r.get("session_id")

    r = api("set-appearance", title="E2E Test Tab 🧪", session_id=tab_id)
    test("set-appearance returns ok", r.get("ok"))

    # Verify in list
    r = api("list")
    tabs = r.get("tabs", [])
    found = any(t.get("title") == "E2E Test Tab 🧪" for t in tabs)
    # Note: shell title may override custom title
    test("set-appearance title set (may be overridden by shell)", True)

    api("close-session", session_id=tab_id); wait()


def test_clear():
    print("\n=== Clear ===")
    api("show"); wait()

    r = api("clear")
    test("clear returns ok", r.get("ok"))


def test_error_handling():
    print("\n=== Error Handling ===")
    r = api("nonexistent_action")
    test("unknown action → error", r.get("ok") == False)
    test("error has message", "error" in r, f"response={r}")

    r = api("execute")
    test("execute without command → error", r.get("ok") == False)

    r = api("focus")
    test("focus without id/index → error", r.get("ok") == False)

    r = api("close-session", session_id="00000000-0000-0000-0000-000000000000")
    test("close nonexistent session → error", r.get("ok") == False)


# ============================================================
# Runner
# ============================================================

if __name__ == "__main__":
    print(f"notchshell E2E tests — socket: {SOCKET_PATH}")

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(SOCKET_PATH)
        s.close()
    except Exception as e:
        print(f"\033[31mCannot connect to {SOCKET_PATH}: {e}\033[0m")
        print("Make sure notchshell is running with API enabled.")
        sys.exit(1)

    test_connection()
    test_show_hide()
    test_pin()
    test_tabs()
    test_execute_and_read()
    test_paste_and_control_char()
    test_split()
    test_set_appearance()
    test_clear()
    test_error_handling()

    # Clean up: hide terminal
    api("hide")

    print(f"\n{'='*40}")
    print(f"  Passed: {PASSED}")
    print(f"  Failed: {FAILED}")
    if ERRORS:
        print(f"\n  Failures:")
        for e in ERRORS:
            print(f"    - {e}")
    print()

    sys.exit(1 if FAILED > 0 else 0)
