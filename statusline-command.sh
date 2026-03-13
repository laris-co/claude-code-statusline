#!/bin/bash

# Claude Code status line — Starship-inspired with icons
# Receives JSON on stdin from Claude Code

input=$(cat)

# One-time capture: save full raw JSON
echo "$input" > /tmp/statusline-raw.json 2>/dev/null

# Extract JSON data
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "~"')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "Claude"')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
used_k=$(echo "$input" | jq -r '((.context_window.current_usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens + .output_tokens) // 0) / 1000 | floor')
max_k=$(echo "$input" | jq -r '(.context_window.context_window_size // 0) / 1000 | floor')

# Shorten /home/user to ~
display_dir="${cwd/#$HOME/\~}"

# Git branch + worktree
git_info=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=""
    if ! git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null; then
      dirty="*"
    fi
    # Check if in a worktree (git dir is a file pointing to main repo)
    wt=""
    git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
    if [ -f "$git_dir" ] || echo "$input" | jq -e '.worktree' >/dev/null 2>&1; then
      wt_name=$(echo "$input" | jq -r '.worktree.name // empty' 2>/dev/null)
      [ -z "$wt_name" ] && wt_name=$(basename "$cwd")
      wt=" 🌳 ${wt_name}"
    fi
    git_info=" on  ${branch}${dirty}${wt}"
  fi
fi

# Auto-compact: key only exists in ~/.claude.json when disabled (false)
# Absent = enabled (default), false = disabled
# When enabled, triggers at ~80% so effective max is 80% of context window
compact_val=$(jq -r 'if .autoCompactEnabled == false then "false" else "true" end' ~/.claude.json 2>/dev/null)
compact_pct=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-80}
if [ "$compact_val" = "false" ]; then
  compact_icon="❌ auto-compact"
else
  compact_icon="🔄 auto-compact"
  max_k=$((max_k * compact_pct / 100))
  # Recalculate pct against effective max
  if [ "$max_k" -gt 0 ]; then
    pct=$((used_k * 100 / max_k))
  fi
fi

# Session duration
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' | cut -d. -f1)
if [ "$duration_ms" -gt 0 ] 2>/dev/null; then
  total_sec=$((duration_ms / 1000))
  dur_h=$((total_sec / 3600))
  dur_m=$(( (total_sec % 3600) / 60 ))
  if [ "$dur_h" -gt 0 ]; then
    duration="${dur_h}h${dur_m}m"
  else
    duration="${dur_m}m"
  fi
else
  duration="0m"
fi

# Save statusline JSON for AI self-awareness
statusline_json="${HOME}/Code/github.com/laris-co/homelab/ψ/active/statusline.json"
if [ -d "$(dirname "$statusline_json")" ]; then
  echo "$input" | jq -c '{
    timestamp: now | todate,
    cwd: (.workspace.current_dir // .cwd),
    model: (.model.display_name // .model.id),
    context_pct: (.context_window.used_percentage // 0),
    cost_usd: (.cost.total_cost_usd // 0),
    duration_ms: (.cost.total_duration_ms // 0),
    version: (.version // "unknown")
  }' > "$statusline_json" 2>/dev/null
fi

# Hostname (show globe for remote machines)
host=$(hostname -s 2>/dev/null || echo "")
if [ -n "$host" ] && [ "$host" != "$(whoami)" ]; then
  host_info="🌐 ${host} "
else
  host_info=""
fi

# Time
now=$(date '+%H:%M')

# Line 1: host + path + branch + key stats (condensed for 2.1.74 which only shows line 1)
echo "${host_info}📂 ${display_dir}${git_info} • ${now} ⏱${duration} • 📊${pct}% (${used_k}k/${max_k}k) ${compact_icon} • 🤖 ${model}"
# Line 2: full stats (shown on 2.1.72, dropped on 2.1.74)
echo "🕐 ${now} ⏱ ${duration} • 📊 ${pct}% (${used_k}k/${max_k}k) • ${compact_icon} • 🤖 ${model}"
