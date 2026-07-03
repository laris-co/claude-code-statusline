#!/bin/bash
# Claude Code statusline — adapted from white.local for m5
# Lines:
#   [optional] 🌱 incubate / 🌳 worktree origin
#   📁 cwd on branch* + token
#   📡 sid prev → • time • pct • skills • model
#   🌐 federation status (cached, async refresh)

# macOS shim: timeout(1) is not in the base system; use gtimeout if installed,
# otherwise drop the duration and run the command directly.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    timeout() { shift; "$@"; }
  fi
fi

input=$(cat)
mkdir -p "/tmp/claude-statusline" 2>/dev/null
echo "$input" > "/tmp/claude-statusline/raw.json" 2>/dev/null

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "~"' 2>/dev/null) || cwd="~"
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"' 2>/dev/null) || model="?"
thinking=$(echo "$input" | jq -r '.thinking.enabled // false' 2>/dev/null)
effort=$(echo "$input" | jq -r '.effort.level // "?"' 2>/dev/null)
fast=$(echo "$input" | jq -r '.fast_mode // false' 2>/dev/null)
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1) || pct=0
used_k=$(echo "$input" | jq -r '((.context_window.current_usage | ((.input_tokens//0)+(.cache_creation_input_tokens//0)+(.cache_read_input_tokens//0)+(.output_tokens//0))) / 1000) | floor' 2>/dev/null) || used_k=0
max_k=$(echo "$input" | jq -r '((.context_window.context_window_size // 0) / 1000) | floor' 2>/dev/null) || max_k=0

# Only override to 1M if CLAUDE_CODE_DISABLE_1M_CONTEXT is NOT set.
if [ "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}" != "1" ]; then
  case "$model" in
    *Opus*4*|*Sonnet*4*|*opus-4*|*sonnet-4*)
      if [ -n "$max_k" ] && [ "$max_k" -le 200 ] 2>/dev/null; then
        max_k=1000
        [ "$used_k" -gt 0 ] 2>/dev/null && pct=$(( (used_k * 100) / max_k ))
        [ "$pct" -gt 100 ] && pct=100
        input=$(echo "$input" | jq -c '.context_window.context_window_size = 1000000 | .context_window.used_percentage = '"$pct"'' 2>/dev/null) || true
      fi
      ;;
  esac
fi

# Detect wrong context_window_size: if used_k overflows max_k, the JSON's
# window size is wrong (Claude Code bug for Opus 4.6/4.7/4.8 1M variants).
# Heuristic: if used > reported window, the real window is 1M.
if [ -n "$used_k" ] && [ -n "$max_k" ] && [ "$max_k" -gt 0 ] && [ "$used_k" -gt "$max_k" ] 2>/dev/null; then
  max_k=1000
  pct=$(( (used_k * 100) / max_k ))
  [ "$pct" -gt 100 ] && pct=100
  input=$(echo "$input" | jq -c '.context_window.context_window_size = 1000000 | .context_window.used_percentage = '"$pct"'' 2>/dev/null) || true
fi
over_flag=""
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null | cut -d. -f1) || dur_ms=0

# Rate limit — Bufo-display style (5h + wk bars with countdowns)
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' 2>/dev/null | cut -d. -f1)
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0' 2>/dev/null | cut -d. -f1)
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' 2>/dev/null | cut -d. -f1)
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0' 2>/dev/null | cut -d. -f1)
# Floor empties to 0
[ -z "$rl_5h_pct" ] && rl_5h_pct=0
[ -z "$rl_7d_pct" ] && rl_7d_pct=0

fmt_until() {
  local secs=$(( ${1:-0} - $(date +%s) ))
  if [ "$secs" -le 0 ]; then echo "now"
  elif [ "$secs" -ge 86400 ]; then echo "$(( secs / 86400 ))d$(( (secs % 86400) / 3600 ))h"
  elif [ "$secs" -ge 3600 ]; then echo "$(( secs / 3600 ))h$(( (secs % 3600) / 60 ))m"
  else echo "$(( secs / 60 ))m"
  fi
}

# 10-segment progress bar — ▓ filled, ░ empty (Bufo LCD aesthetic)
qbar() {
  local pct=${1:-0}
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  [ "$pct" -lt 0 ]   2>/dev/null && pct=0
  local filled=$(( (pct + 5) / 10 ))   # round to nearest 10%
  local i b=""
  for ((i=0; i<filled; i++)); do b="${b}▓"; done
  for ((i=filled; i<10; i++)); do b="${b}░"; done
  echo "$b"
}

# Status dot — green <50, yellow 50-79, red 80+
qdot() {
  local pct=${1:-0}
  if   [ "$pct" -ge 80 ] 2>/dev/null; then echo "🔴"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then echo "🟡"
  else echo "🟢"
  fi
}

rl_5h_line=""
rl_wk_line=""
[ "${rl_5h_reset:-0}" != "0" ] && rl_5h_line="$(qdot ${rl_5h_pct}) 5h  $(qbar ${rl_5h_pct}) ${rl_5h_pct}% $(fmt_until ${rl_5h_reset:-0})"
[ "${rl_7d_reset:-0}" != "0" ] && rl_wk_line="$(qdot ${rl_7d_pct}) wk  $(qbar ${rl_7d_pct}) ${rl_7d_pct}% $(fmt_until ${rl_7d_reset:-0})"

# Duration
s=$(( dur_ms / 1000 )) 2>/dev/null || s=0
h=$(( s / 3600 )); m=$(( (s % 3600) / 60 ))
[ "$h" -gt 0 ] 2>/dev/null && dur="${h}h${m}m" || dur="${m}m"

# Auto-compact
ac="❌"
jq -e '.autoCompactEnabled != false' ~/.claude.json >/dev/null 2>&1 && ac="✅"

# Git branch (timeout to avoid hangs)
branch=$(timeout 2 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
git=""
if [ -n "$branch" ]; then
  d=""; timeout 1 git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null || d="*"
  wt=""; [ -f "$cwd/.git" ] && wt=" 🌳"
  git="  ${branch}${d}${wt}"
fi

# Active Claude token — identify by the SESSION's real credential (inherited env),
# never the directory's .envrc label: `token-cli use` while a session runs flips
# the directory label but not the session's auth (2026-07-03 argus mislabel bug).
tok=""
TOK_MAP="$HOME/.oracle/token-hash-map"
# Precedence mirrors Claude Code's documented credential order (authentication docs):
# AUTH_TOKEN > API_KEY > OAUTH_TOKEN > /login. (Approximation: an interactively
# declined API key would fall through to OAuth, which env inspection can't see.)
real_cred="${ANTHROPIC_AUTH_TOKEN:-${ANTHROPIC_API_KEY:-${CLAUDE_CODE_OAUTH_TOKEN:-}}}"
if [ -n "$real_cred" ]; then
  cred_hash=$(printf '%s' "$real_cred" | shasum -a 256 | cut -c1-8)
  [ -f "$TOK_MAP" ] && tok=$(awk -v h="$cred_hash" '$1==h{print $2; exit}' "$TOK_MAP" 2>/dev/null)
  if [ -z "$tok" ]; then
    tok="#$(printf '%s' "$cred_hash" | cut -c1-5)"
    # Refresh hash→name map from pass, async, at most hourly (touch = debounce).
    if [ ! -f "$TOK_MAP" ] || [ -n "$(find "$TOK_MAP" -mmin +60 2>/dev/null)" ]; then
      mkdir -p "$HOME/.oracle"; touch "$TOK_MAP"
      ( for name in $(pass ls claude 2>/dev/null | grep -o 'token-[A-Za-z0-9._-]*' | sort -u); do
          v=$(pass show "claude/$name" 2>/dev/null | head -1 | tr -d '\n')
          [ -n "$v" ] && printf '%s %s\n' "$(printf '%s' "$v" | shasum -a 256 | cut -c1-8)" "${name#token-}"
        done > "$TOK_MAP.tmp.$$"
        # gpg can fail silently in a detached shell — never install an empty map
        if [ -s "$TOK_MAP.tmp.$$" ]; then mv "$TOK_MAP.tmp.$$" "$TOK_MAP"; else rm -f "$TOK_MAP.tmp.$$"; fi ) >/dev/null 2>&1 &
    fi
  fi
else
  # No env credential → session runs on the machine's OAuth login.
  # Hash the refreshToken from credentials file — stable per-account (doesn't
  # rotate every API call like accessToken), and reverse-map through the same map.
  rt=$(jq -r '.claudeAiOauth.refreshToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  if [ -n "$rt" ]; then
    cred_hash=$(printf '%s' "$rt" | shasum -a 256 | cut -c1-8)
    [ -f "$TOK_MAP" ] && tok=$(awk -v h="$cred_hash" '$1==h{print $2; exit}' "$TOK_MAP" 2>/dev/null)
    [ -z "$tok" ] && tok="#$(printf '%s' "$cred_hash" | cut -c1-5)"
  else
    tok="#oauth"
  fi
fi
tok_info=""
[ -n "$tok" ] && tok_info=" 🔐${tok}"

# Shorten path to org/repo (strip ghq root prefix)
GHQ_ROOT=$(ghq root 2>/dev/null || echo "$HOME/Code")
dir="${cwd/#${GHQ_ROOT}\/github.com\//}"
dir="${dir/#github.com\//}"
# Fallback: if nothing was stripped, replace $HOME with ~
[ "$dir" = "$cwd" ] && dir="${cwd/#$HOME/\~}"


# Session ID (short)
sid=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null | cut -c1-8)

# Previous session ID
ENCODED_CWD=$(echo "$cwd" | sed 's|/|-|g; s|\.|-|g')
PROJ_DIR="$HOME/.claude/projects/${ENCODED_CWD}"
prev_sid=$(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null | head -2 | tail -1 | xargs -I{} basename {} .jsonl 2>/dev/null | cut -c1-8)
prev_info=""
[ -n "$prev_sid" ] && [ "$prev_sid" != "$sid" ] && prev_info="${prev_sid} → "

# Incubation detection — set 🌱 if cwd path contains /ψ/incubate/.
# Cheap substring check (no filesystem walk) — see issue laris-co/claude-code-statusline#1.
incubate=""
case "$cwd" in
  */ψ/incubate/*)
    parent=$(echo "$cwd" | sed "s|.*/\([^/]*\)/ψ/incubate/.*|\1|; s|\.wt-.*||")
    incubate=" 🌱 ${parent}"
    ;;
esac

# Worktree origin detection — find which .wt-* project dir owns this session
sid_full=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
wt_dir=""
for pdir in "$HOME"/.claude/projects/*wt-*; do
  [ -f "$pdir/${sid_full}.jsonl" ] || continue
  pname=$(basename "$pdir")
  for d in "$HOME"/Code/github.com/*/*.wt-*; do
    [ -d "$d" ] || continue
    encoded=$(echo "$d" | sed 's|/|-|g; s|\.|-|g')
    [ "$pname" = "$encoded" ] && wt_dir="$d" && break
  done
  break
done 2>/dev/null
wt_info=""
if [ -n "$wt_dir" ] && [ "$wt_dir" != "$cwd" ]; then
  wt_short="${wt_dir/#$HOME\/Code\/github.com\//}"
  wt_branch=$(timeout 2 git -C "$wt_dir" symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$wt_branch" ] && wt_info=" 🌳 ${wt_short} on  ${wt_branch}"
fi

# Federation status (cached, async refresh — never blocks the prompt)
FED_BAR="${GHQ_ROOT}/github.com/Soul-Brews-Studio/m5-federation-oracle/scripts/fed-status-bar.sh"
fed_line=""
if [ -x "$FED_BAR" ]; then
  fed_line="$("$FED_BAR" 2>/dev/null)"
fi

host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname)

# MQTT publish — fire-and-forget telemetry to mqtt.laris.co.
# Topic: claude/<machine>/<user>/<oracle>/<session>
# Backgrounded so it never blocks prompt render. -r retained so subscribers get latest state on connect.
# Password from pass store (mqtt/laris-co/nat).
if command -v mosquitto_pub >/dev/null 2>&1 && command -v pass >/dev/null 2>&1; then
  mqtt_host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
  mqtt_user=$(whoami)
  # Walk up dirs to find CLAUDE.md with "**I am**:" line — handles subdir cwd.
  mqtt_oracle=""
  walk_dir="$cwd"
  for _ in 1 2 3 4 5; do
    if [ -f "$walk_dir/CLAUDE.md" ]; then
      cand=$(grep -E "^\*\*I am\*\*:" "$walk_dir/CLAUDE.md" 2>/dev/null | sed -E 's/.*: //; s/ —.*//' | tr '[:upper:]' '[:lower:]' | head -1)
      [ -n "$cand" ] && mqtt_oracle="$cand" && break
    fi
    parent=$(dirname "$walk_dir")
    [ "$parent" = "$walk_dir" ] && break
    walk_dir="$parent"
  done
  # Fallback: use git toplevel basename minus -oracle suffix.
  if [ -z "$mqtt_oracle" ]; then
    top=$(timeout 1 git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    mqtt_oracle=$(basename "${top:-$cwd}" | sed 's/-oracle$//' | tr '[:upper:]' '[:lower:]')
  fi
  mqtt_topic="claude/${mqtt_host}/${mqtt_user}/${mqtt_oracle}/${sid:-unknown}"
  mqtt_pass=$(timeout 1 pass show mqtt/laris-co/nat 2>/dev/null)
  if [ -n "$mqtt_pass" ]; then
    # Enrich payload with branch / worktree / fed / oracle that aren't in raw input.
    published_at=$(($(date +%s) * 1000))   # millisecond epoch
    enriched=$(echo "$input" | jq -c \
      --arg branch "${branch:-}" \
      --arg wt_short "${wt_short:-}" \
      --arg wt_branch "${wt_branch:-}" \
      --arg fed "${fed_line:-}" \
      --arg oracle "$mqtt_oracle" \
      --arg machine "$mqtt_host" \
      --arg dir "$dir" \
      --arg dirty "${d:-}" \
      --arg account "${tok:-}" \
      --argjson published_at "$published_at" \
      --argjson corrected_max_k "${max_k:-0}" \
      --argjson corrected_used_k "${used_k:-0}" \
      --argjson corrected_pct "${pct:-0}" \
      --argjson remaining_k "$(( max_k - used_k > 0 ? max_k - used_k : 0 ))" \
      '. + {oracle: $oracle, machine: $machine, branch: $branch, branch_dirty: ($dirty != ""), worktree: $wt_short, worktree_branch: $wt_branch, federation: $fed, short_dir: $dir, account: $account, published_at: $published_at, context_window: (.context_window + {corrected_window_size: ($corrected_max_k * 1000), corrected_used_k: $corrected_used_k, corrected_pct: $corrected_pct, remaining_k: $remaining_k})}' \
      2>/dev/null)
    [ -z "$enriched" ] && enriched="$input"
    (printf '%s' "$enriched" | mosquitto_pub -h mqtt.laris.co -p 1883 -u nat -P "$mqtt_pass" -t "$mqtt_topic" -s -q 0 -r &) 2>/dev/null
  fi
fi

# Oracle skills version (used on host line + footer)
skl_ver=$(head -3 ~/.claude/skills/rrr/SKILL.md 2>/dev/null | grep -o 'v[0-9.]*' | head -1)

[ -n "$wt_info" ] && echo "${incubate}${wt_info}"
echo "🖥  ${host}  📁 ${dir}${git}${tok_info}  ·  🔮${skl_ver:-?}"
[ -n "$incubate" ] && echo "   📂 ${cwd}"

ctx_dot=$(qdot ${pct:-0})
ctx_bar=$(qbar ${pct:-0})
# Reasoning mode tag
reason_tag=""
if [ "$fast" = "true" ]; then
  reason_tag=" ⚡fast"
elif [ "$thinking" = "true" ]; then
  reason_tag=" 🧠${effort}"
fi
# Header line — sid · time · model · reasoning · fed · version (all meta together)
echo "📡 ${prev_info}${sid} • $(date +%H:%M) • ${model}${reason_tag}"
# 3 clean bars stacked: ctx / 5h+fed / wk
echo "${ctx_dot} ctx ${ctx_bar} ${pct}% ${used_k}k${over_flag}/${max_k}k"
if [ -n "$rl_5h_line" ] && [ -n "$fed_line" ]; then
  echo "${rl_5h_line}  🌐 ${fed_line}"
elif [ -n "$rl_5h_line" ]; then
  echo "$rl_5h_line"
elif [ -n "$fed_line" ]; then
  echo "🌐 ${fed_line}"
fi
[ -n "$rl_wk_line" ] && echo "$rl_wk_line"

# Per-token usage snapshot — append-only ~/.claude/token-usage.jsonl.
# Backgrounded + fully guarded: can never block or break the statusline.
# Throttling (5 min per token) happens inside token-usage itself.
{ (printf '%s' "$input" | "$HOME/.local/bin/token-usage" log >/dev/null 2>&1 &) ; } 2>/dev/null || true
