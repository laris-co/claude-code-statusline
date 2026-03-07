#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/statusline-command.sh"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing Claude Code Starship Status Line..."

# Copy script
cp "$SCRIPT_DIR/statusline-command.sh" "$DEST"
chmod +x "$DEST"
echo "✓ Installed $DEST"

# Check if settings.json exists and has statusLine config
if [ -f "$SETTINGS" ]; then
  if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "✓ statusLine already configured in $SETTINGS"
  else
    # Add statusLine to existing settings
    jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}}' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "✓ Added statusLine to $SETTINGS"
  fi
else
  echo "⚠ $SETTINGS not found. Add this manually:"
  echo ''
  echo '  {"statusLine": {"type": "command", "command": "~/.claude/statusline-command.sh"}}'
fi

echo ""
echo "Done! Restart Claude Code to see your new status line."
echo ""
echo "  🕐 12:00 📂 ~/project on  main • 🤖 Opus 4.6 • 📊 28% (56k/160k) • 🔄 auto-compact"
