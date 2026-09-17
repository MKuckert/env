#!/usr/bin/env bash

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

reset=$'\033[0m'
bold=$'\033[1m'
dim=$'\033[2m'
fore_violet=$'\033[38;5;97m'
fore_white=$'\033[38;5;253m'
fore_red=$'\033[38;5;160m'
fore_orange=$'\033[38;5;202m'
fore_green=$'\033[38;5;70m'
fore_grey=$'\033[38;5;245m'
fore_blue=$'\033[38;5;74m'

if [ -n "$worktree" ]; then
  # In a linked worktree: show the worktree name instead of the path.
  dir_display="󰙅 ${worktree}"
else
  # Trim path like PROMPT_DIRTRIM=2 (keep last 2 segments)
  dir_display="$cwd"
  IFS='/' read -ra parts <<< "$dir_display"
  count=${#parts[@]}
  if [ "$count" -gt 2 ]; then
    last2=("${parts[@]: -2}")
    dir_display="…/$(IFS=/; echo "${last2[*]}")"
  fi
fi

branch_segment=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree &>/dev/null; then
  branchColor="$fore_green"
  branchIcon="󱓏"

  # Uncommitted changes in the index
  if ! git -C "$cwd" --no-optional-locks diff --quiet --ignore-submodules --cached 2>/dev/null; then
    branchColor="$fore_red"
    branchIcon="󱓊"
  # Unstaged changes
  elif ! git -C "$cwd" --no-optional-locks diff-files --quiet --ignore-submodules -- 2>/dev/null; then
    branchColor="$fore_orange"
    branchIcon="󱓍"
  # Untracked files
  elif [ -n "$(git -C "$cwd" --no-optional-locks ls-files --others --exclude-standard)" ]; then
    branchColor="$fore_green"
    branchIcon="󰘬"
  fi

  branchName=$(git -C "$cwd" --no-optional-locks symbolic-ref --quiet --short HEAD 2>/dev/null)
  [ -z "$branchName" ] && branchName=$(git -C "$cwd" --no-optional-locks describe --all --exact-match HEAD 2>/dev/null)
  [ -z "$branchName" ] && branchName=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  [ -z "$branchName" ] && branchName="?"

  branch_segment=" ${fore_white}${branchIcon}${branchColor}${branchName}${reset}"
fi

# --- Usage segments ---------------------------------------------------------

model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
# Drop the trailing "(1M context)" note — the context window is already shown
# in its own usage segment.
model_name=$(echo "$model_name" | sed -E 's/ *\(1M context\)//')
model_id=$(echo "$input" | jq -r '.model.id // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Context window limit: 1M variants carry "1m" in the model id, everything
# else is a 200k window.
if [[ "$model_id" == *1m* || "$model_id" == *1M* ]]; then
  ctx_limit=1000000
else
  ctx_limit=200000
fi

# Prefer harness-provided context numbers; fall back to the last assistant
# message in the transcript (input + cache_creation + cache_read).
used=$(echo "$input" | jq -r '.context.used_tokens // empty')
if [ -z "$used" ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Only the tail is scanned — transcripts grow to many MB and this runs on
  # every statusline render.
  used=$(tail -n 400 "$transcript" 2>/dev/null | jq -s -r '
    [ .[] | select(.type == "assistant" and .message.usage) ] | last
    | if . then
        (.message.usage.input_tokens        // 0)
      + (.message.usage.cache_creation_input_tokens // 0)
      + (.message.usage.cache_read_input_tokens     // 0)
      else empty end
  ' 2>/dev/null)
fi

ctx_segment=""
if [ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null; then
  pct=$(( used * 100 / ctx_limit ))
  if   [ "$pct" -ge 80 ]; then ctxColor="$fore_red"
  elif [ "$pct" -ge 50 ]; then ctxColor="$fore_orange"
  else                         ctxColor="$fore_green"
  fi
  if [ "$used" -ge 1000 ]; then
    used_display="$(( used / 1000 ))k"
  else
    used_display="$used"
  fi

  if [ "$ctx_limit" -ge 1000000 ]; then
    limit_display="$(( ctx_limit / 1000000 ))M"
  elif [ "$ctx_limit" -ge 1000 ]; then
    limit_display="$(( ctx_limit / 1000 ))k"
  else
    limit_display="$ctx_limit"
  fi

  ctx_segment=" ${dim}${fore_grey}│${reset} ${ctxColor}${used_display}${reset}${dim}${fore_grey}/${limit_display} ${pct}%${reset}"
fi

effort_level=$(echo "$input" | jq -r '.effort.level // empty')
model_display="$model_name"
[ -n "$effort_level" ] && model_display="${model_name} (${effort_level})"

model_segment=""
[ -n "$model_name" ] && model_segment=" ${dim}${fore_grey}│${reset} ${fore_blue}${model_display}${reset}"

# --- Prompt cache TTL (5m vs 1h) --------------------------------------------

cache_segment=""
# Read as an explicit boolean (not // empty) so a real `false` isn't treated
# as "field missing" — jq's // treats false as absent.
cache_observed=$(echo "$input" | jq -r 'if .prompt_cache.caching_observed == true then "true" elif .prompt_cache.caching_observed == false then "false" else empty end')
if [ "$cache_observed" = "true" ]; then
  cache_ttl=$(echo "$input" | jq -r '.prompt_cache.ttl // empty')
  cache_warm=$(echo "$input" | jq -r '.prompt_cache.warm // empty')
  # Floor to an integer in the same jq call: expires_at can come back with a
  # fractional part, and `[ "$x" -gt 0 ]` / `date -r "$x"` below both fail
  # silently (stderr redirected) on a non-integer string — that was why the
  # expiry time never rendered before.
  cache_expires=$(echo "$input" | jq -r '.prompt_cache.expires_at | select(. != null) | floor')
  if [ -n "$cache_ttl" ]; then
    if [ "$cache_warm" = "true" ]; then
      cacheColor="$fore_green"
      cacheIcon="●"
    else
      cacheColor="$fore_red"
      cacheIcon="○"
    fi
    expiry_display=""
    if [ -n "$cache_expires" ] && [ "$cache_expires" -gt 0 ] 2>/dev/null; then
      now_epoch=$(date +%s)
      remaining=$(( cache_expires - now_epoch ))
      if [ "$remaining" -gt 0 ]; then
        expiry_time=$(date -d "@$cache_expires" +%H:%M 2>/dev/null || /bin/date -r "$cache_expires" +%H:%M 2>/dev/null)
        [ -n "$expiry_time" ] && expiry_display="→${expiry_time}"
      else
        expiry_display=" stale"
      fi
    fi
    cache_segment=" ${dim}${fore_grey}│${reset} ${cacheColor}${cacheIcon}${cache_ttl}${expiry_display}${reset}"
  fi
elif [ "$cache_observed" = "false" ]; then
  cache_segment=" ${dim}${fore_grey}│${reset} ${fore_orange}uncached${reset}"
fi

# --- Session duration --------------------------------------------------------

duration_segment=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  session_start=$(jq -r 'select(.timestamp != null) | .timestamp' "$transcript" 2>/dev/null | head -n 1)
  if [ -n "$session_start" ]; then
    clean_start="${session_start%Z}"
    clean_start="${clean_start%.*}"
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_start" +%s 2>/dev/null)
    if [ -n "$start_epoch" ]; then
      now_epoch=$(date +%s)
      diff=$(( now_epoch - start_epoch ))
      [ "$diff" -lt 0 ] && diff=0
      hours=$(( diff / 3600 ))
      mins=$(( (diff % 3600) / 60 ))
      if [ "$hours" -gt 0 ]; then
        dur_display="${hours}h${mins}m"
      else
        dur_display="${mins}m"
      fi
      duration_segment=" ${dim}${fore_grey}│${reset} ${fore_grey}⏱ ${dur_display}${reset}"
    fi
  fi
fi

cost_segment=""
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost" ]; then
  cost_segment=" ${dim}${fore_grey}│ \$$(printf '%.2f' "$cost")${reset}"
fi

printf '%s' "${bold}${fore_violet}${dir_display}${reset}${branch_segment}${model_segment}${ctx_segment}${cache_segment}${duration_segment}${cost_segment}"
