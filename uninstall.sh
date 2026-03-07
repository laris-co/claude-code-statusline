#!/bin/bash
set -e

DEST="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "Uninstalling Claude Code Starship Status Line..."

# Remove script
if [ -f "$DEST" ]; then
  rm "$DEST"
  echo "✓ Removed $DEST"
fi

# Remove statusLine from settings
if [ -f "$SETTINGS" ] && jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
  jq 'del(.statusLine)' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "✓ Removed statusLine from $SETTINGS"
fi

echo "Done! Restart Claude Code to use the default status line."
