# Claude Code Starship Status Line

A Starship-inspired status line for [Claude Code](https://claude.ai/claude-code) CLI with icons, git info, context usage, and auto-compact detection.

```
🕐 12:35 📂 ~/my-project on  main* • 🤖 Opus 4.6 • 📊 35% (56k/160k) • 🔄 auto-compact
```

Auto-adapts to narrow terminals:

```
🕐 12:35 📂 ~/my-project on  main* • 🤖 Opus 4.6
📊 35% (56k/160k) • 🔄 auto-compact
```

## Features

| Icon | Info |
|------|------|
| 🕐 | Current time |
| 📂 | Working directory (with `~` for home) |
|  | Git branch + dirty indicator (`*`) |
| 🌳 | Git worktree name (when in a worktree) |
| 🤖 | Model name (Opus 4.6, Sonnet 4.6, etc.) |
| 📊 | Context usage — % and tokens (used/effective max) |
| 🔄/❌ | Auto-compact on/off |

### Effective context window

When auto-compact is **enabled**, it triggers at ~80% of the context window. You never actually get to use the full 200k — compaction kicks in at ~160k. The status line shows the **effective** usable limit:

- **Auto-compact on**: `📊 35% (56k/160k)` — effective limit
- **Auto-compact off**: `📊 28% (56k/200k)` — full window

## Install

```bash
git clone https://github.com/nazt/claude-code-statusline.git
cd claude-code-statusline
bash install.sh
```

Or manually:

```bash
# Copy the script
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

## Uninstall

```bash
bash uninstall.sh
```

## Requirements

- [jq](https://jqlang.github.io/jq/) — JSON parsing
- git — branch detection
- A font with emoji support

## How it works

Claude Code pipes JSON to your script's stdin on every interaction:

```json
{
  "model": { "id": "claude-opus-4-6", "display_name": "Opus 4.6" },
  "workspace": { "current_dir": "/home/user/project" },
  "context_window": {
    "used_percentage": 28,
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 3,
      "output_tokens": 94,
      "cache_creation_input_tokens": 372,
      "cache_read_input_tokens": 55664
    }
  },
  "cost": { "total_cost_usd": 1.55 },
  "version": "2.1.71"
}
```

### The auto-compact discovery

The auto-compact status isn't in the statusLine JSON. We found it by digging through the Claude Code binary:

- `autoCompactEnabled` lives in `~/.claude.json` (home root, **not** `~/.claude/.claude.json`)
- The key **only exists when set to `false`** — when enabled (default), it's absent
- jq's `//` operator treats `false` as falsy — use `if .autoCompactEnabled == false` instead

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `80` | Auto-compact trigger threshold (%) |

## Customization

Edit `~/.claude/statusline-command.sh` to add more fields:

- `cost.total_cost_usd` — session spend
- `cost.total_duration_ms` — session duration
- `vim.mode` — vim mode (NORMAL/INSERT/etc.)
- `worktree.name` — Claude Code worktree name
- `output_style.name` — output style

## License

MIT
