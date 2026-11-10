#!/usr/bin/env bash
# Claude Code status line — mirrors Powerlevel10k prompt segments:
#   dir | git branch+status | node version | model | context usage

input=$(cat)

# --- Directory ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$cwd" ]; then
  # Shorten home directory to ~
  home="$HOME"
  short_cwd="${cwd/#$home/\~}"
else
  short_cwd="$(pwd)"
  short_cwd="${short_cwd/#$HOME/\~}"
fi

# --- Git branch & dirty status ---
git_info=""
if git -C "$cwd" rev-parse --git-dir --no-optional-locks > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=$(git -C "$cwd" status --porcelain --no-optional-locks 2>/dev/null | head -1)
    if [ -n "$dirty" ]; then
      git_info=" $branch *"
    else
      git_info=" $branch"
    fi
  fi
fi

# --- Node version (from nvm if available) ---
node_info=""
if command -v node > /dev/null 2>&1; then
  node_ver=$(node --version 2>/dev/null)
  [ -n "$node_ver" ] && node_info=" node:$node_ver"
fi

# --- Claude model (short name) ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
model_info=""
[ -n "$model" ] && model_info=" $model"

# --- Context usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_info=""
if [ -n "$used_pct" ]; then
  ctx_info=$(printf " ctx:%.0f%%" "$used_pct")
fi

# --- Rate limits (5h) ---
rate_info=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five_pct" ]; then
  rate_info=$(printf " 5h:%.0f%%" "$five_pct")
fi

# --- Assemble & print with ANSI colors ---
# Colors: cyan=dir, magenta=git, green=node, blue=model, yellow=ctx
printf "\033[36m%s\033[0m" "$short_cwd"
[ -n "$git_info" ]   && printf "\033[35m%s\033[0m" "$git_info"
[ -n "$node_info" ]  && printf "\033[32m%s\033[0m" "$node_info"
[ -n "$model_info" ] && printf "\033[34m%s\033[0m" "$model_info"
[ -n "$ctx_info" ]   && printf "\033[33m%s\033[0m" "$ctx_info"
[ -n "$rate_info" ]  && printf "\033[31m%s\033[0m" "$rate_info"
printf "\n"
