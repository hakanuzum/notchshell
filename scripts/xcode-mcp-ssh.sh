#!/bin/bash
# Proxy Xcode MCP server over SSH.
# Forwards stdio to `xcrun mcpbridge` running on the remote VM.
# Usage: Add as MCP server in Claude Code config.

REMOTE_HOST="maksimnagaev@macos.shared"
SSH_KEY="$HOME/.ssh/id_homelab"

exec ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR "$REMOTE_HOST" "xcrun mcpbridge"
