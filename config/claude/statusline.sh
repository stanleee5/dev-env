#!/bin/bash
input=$(cat)

# ── Parse JSON ───────────────────────────────────────────────────
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "Unknown Model")",
  @sh "used=\(.context_window.used_percentage // 0)",
  @sh "used_tokens=\(.context_window.total_input_tokens // 0)",
  @sh "output_tokens=\(.context_window.total_output_tokens // 0)",
  @sh "current_dir=\(.worktree.original_cwd // .workspace.current_dir // .cwd // "")",
  @sh "worktree=\(.worktree.name // "")",
  @sh "total_cost=\(.cost.total_cost_usd // 0)",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "rl_5h_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "rl_5h_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "rl_7d_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "rl_7d_reset=\(.rate_limits.seven_day.resets_at // "")"
')"
[ -n "$rl_5h_pct" ] && rl_5h_pct=$(printf "%.0f" "$rl_5h_pct")
[ -n "$rl_7d_pct" ] && rl_7d_pct=$(printf "%.0f" "$rl_7d_pct")

# ── Colors ───────────────────────────────────────────────────────
G=$'\033[38;2;78;201;176m'   Y=$'\033[38;2;255;215;0m'
O=$'\033[38;2;255;140;0m'    C=$'\033[38;2;91;206;250m'
P=$'\033[38;2;255;150;200m'  V=$'\033[38;2;180;130;255m'
BE=$'\033[38;2;60;60;60m'    R=$'\033[0m'

# ── Helpers ──────────────────────────────────────────────────────
bar() {
  local pct=$1 w=10 t f r i b="" e=""
  t=$(( pct * w * 8 / 100 )); f=$(( t / 8 )); r=$(( t % 8 ))
  for (( i=0; i<f; i++ )); do b+="█"; done
  local n=$f
  if (( r > 0 && f < w )); then
    local p=(▏ ▎ ▍ ▌ ▋ ▊ ▉); b+="${p[$((r-1))]}"; (( n++ ))
  fi
  for (( i=n; i<w; i++ )); do e+="█"; done
  printf "${P}%s${BE}%s${R}" "$b" "$e"
}

ftime() {
  local s=$(( $1 / 1000 )) h m sec
  h=$(( s/3600 )); m=$(( s%3600/60 )); sec=$(( s%60 ))
  if   (( h > 0 )); then printf "%dh%02dm" $h $m
  elif (( m > 0 )); then printf "%dm%02ds" $m $sec
  else                    printf "%ds" $sec
  fi
}

fremain() {
  local d=$(( $1 - $(date +%s) ))
  (( d <= 0 )) && { printf "0m"; return; }
  local dy=$(( d/86400 )) h=$(( d%86400/3600 )) m=$(( d%3600/60 ))
  if   (( dy > 0 )); then printf "%dd%dh" $dy $h
  elif (( h > 0 ));  then printf "%dh%02dm" $h $m
  else                     printf "%dm" $m
  fi
}

frl() {
  [ -z "$1" ] && { printf "%s %s n/a" "$3" "$4"; return; }
  local rm=""; [ -n "$2" ] && rm=" ($(fremain "$2"))"
  printf "%s %s %s%%%s" "$3" "$4" "$1" "$rm"
}

# ── Line 1 ───────────────────────────────────────────────────────
root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir=$(basename "$root")
fi=$(printf '\xf3\xb0\x89\x8b')

git_s="no branch"
if [ -n "$current_dir" ] && git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
  br=$(git -C "$current_dir" branch --show-current 2>/dev/null)
  [ -z "$br" ] && br=$(git -C "$current_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  st=$(git -C "$current_dir" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  mo=$(git -C "$current_dir" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  git_s="$br"
  (( st > 0 )) && git_s+=" $(printf "${G}+${st}${R}")"
  (( mo > 0 )) && git_s+=" $(printf "${Y}~${mo}${R}")"
fi

wt="${worktree:-no worktree}"
dur=$(printf "${V}󱎫 %s (%s)${R}" "$(ftime "$duration_ms")" "$(date '+%H:%M')")

# ── Line 2 ───────────────────────────────────────────────────────
pct=$(printf "%.0f" "$used")
tok=$(( used_tokens + output_tokens ))
cost=$(printf "%.2f" "$total_cost")

if (( tok >= 1000000 )); then tk=$(awk "BEGIN{printf \"%.1fM\",$tok/1000000}")
else                          tk=$(awk "BEGIN{printf \"%.1fK\",$tok/1000}")
fi

l2_usage="${P}󰆼 ${R}$(bar "$pct")$(printf " ${P}${pct}%%${R}")"
l2_tok=$(printf "${P}󰈙 %s${R}" "$tk")
l2_cost=$(printf "${P}\$%s${R}" "$cost")
l2_5h=$(frl "$rl_5h_pct" "$rl_5h_reset" "󰥔" "5h")
l2_7d=$(frl "$rl_7d_pct" "$rl_7d_reset" "󰃭" "7d")

# ── Output ───────────────────────────────────────────────────────
printf "${O}󰍛 %s${R} | ${G}%s %s${R} · ${C}%s${R} | %s | %s\n%s  %s  %s  %s  %s" \
  "$model" "$fi" "$dir" "$git_s" "$wt" "$dur" \
  "$l2_usage" "$l2_tok" "$l2_cost" "$l2_5h" "$l2_7d"
