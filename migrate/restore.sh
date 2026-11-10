#!/bin/bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--all-repos] [--recent-days N] [step ...]

Steps (default: all, in this order): secrets claude mem repos loose
  secrets  unpack secrets.dmg into ~ (never overwrites existing files)
  claude   restore ~/.claude data and merge user MCP servers into ~/.claude.json
  mem      restore ~/.claude-mem (claude-mem worker must be stopped)
  repos    clone repos used in the last N days (default 45) or with local-only work,
           then replay unpushed branches, stashes and dirty worktrees
  loose    copy non-repo files back into ~/GitProjects (never overwrites)

Run after ~/dotfiles/install.sh.
EOF
}

SRC="$(cd "$(dirname "$0")" && pwd)"
ALL_REPOS=0
RECENT_DAYS=45
STEPS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all-repos) ALL_REPOS=1 ;;
    --recent-days) RECENT_DAYS="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) STEPS+=("$1") ;;
  esac
  shift
done
[ ${#STEPS[@]} -gt 0 ] || STEPS=(secrets claude mem repos loose)

# shellcheck source=/dev/null
. "$SRC/manifest.env"
TS="$(date +%Y%m%d%H%M%S)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

encode_path() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

rewrite_home() {
  [ "$OLD_HOME" = "$HOME" ] && return
  local f
  for f in "$@"; do
    if [ -f "$f" ]; then
      sed -i '' "s|$OLD_HOME|$HOME|g" "$f"
    fi
  done
}

place_repo_files() {
  local stage="$HOME/.migration-repo-files" rel key left
  [ -f "$stage/MANIFEST" ] || return 0
  left="$(mktemp)"
  while read -r rel; do
    [ -n "$rel" ] || continue
    key="$(printf '%s' "$rel" | tr '/' '_')"
    if [ -d "$HOME/$rel/.git" ]; then
      rsync -a --ignore-existing "$stage/$key/" "$HOME/$rel/"
      rm -rf "${stage:?}/$key"
      echo "  placed ignored files (.env etc.) into $rel"
    else
      echo "$rel" >> "$left"
    fi
  done < "$stage/MANIFEST"
  if [ -s "$left" ]; then
    mv "$left" "$stage/MANIFEST"
    log "Repo .env files waiting for $(wc -l < "$stage/MANIFEST" | tr -d ' ') repos not cloned yet (placed by the repos step)"
  else
    rm -f "$left"
    rm -rf "$stage"
  fi
}

report_agents() {
  local plist
  for plist in "$HOME"/Library/LaunchAgents/*.plist; do
    [ -f "$plist" ] || continue
    if [ "$OLD_HOME" != "$HOME" ] && grep -q "$OLD_HOME" "$plist"; then
      sed -i '' "s|$OLD_HOME|$HOME|g" "$plist"
    fi
    if grep -q "$HOME" "$plist" && ! launchctl list "$(basename "$plist" .plist)" >/dev/null 2>&1; then
      warn "LaunchAgent restored but NOT started: $(basename "$plist")"
      echo "    start it when ready: launchctl bootstrap gui/$(id -u) \"$plist\""
    fi
  done
  if [ -f "$HOME/.migration-crontab" ]; then
    warn "Old crontab saved to ~/.migration-crontab (not installed; paths may point to data not migrated)"
    echo "    review, then install with: crontab ~/.migration-crontab"
  fi
}

restore_secrets() {
  [ -f "$SRC/secrets.dmg" ] || { warn "no secrets.dmg, skipping"; return; }
  log "Secrets: mounting secrets.dmg"
  local mnt pw
  mnt="$(mktemp -d)"
  read -rsp "  DMG password: " pw; echo
  printf '%s' "$pw" | hdiutil attach -quiet -nobrowse -stdinpass -mountpoint "$mnt" "$SRC/secrets.dmg"
  ls -A "$mnt" | grep -vxE '\.(fseventsd|Trashes|Spotlight-V100)' \
    | (cd "$mnt" && tr '\n' '\0' | tar --null -T - -cf -) \
    | tar -C "$HOME" -xkpf - 2>&1 | grep -v 'File exists' || true
  hdiutil detach -quiet "$mnt"
  rmdir "$mnt" 2>/dev/null || true
  rewrite_home "$HOME/.kube/config" "$HOME/.ssh/config" "$HOME/.aws/config"
  [ -d "$HOME/.migration-repo-files" ] && chmod 700 "$HOME/.migration-repo-files"
  place_repo_files
  report_agents
  if [ -d "$HOME/.ssh" ]; then
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} +
  fi
  log "Secrets: restored (existing files kept). Re-login: aws sso login, saml2aws login, gh auth status"
}

restore_claude() {
  log "Claude: restoring ~/.claude"
  mkdir -p "$HOME/.claude"
  [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.pre-restore-$TS"
  rsync -a --exclude /claude-json-extract.json "$SRC/claude/" "$HOME/.claude/"

  local old_enc new_enc d
  old_enc="$(encode_path "$OLD_HOME")"
  new_enc="$(encode_path "$HOME")"
  if [ "$old_enc" != "$new_enc" ]; then
    log "Claude: remapping project dirs $old_enc* -> $new_enc*"
    for d in "$HOME/.claude/projects/$old_enc"*; do
      [ -e "$d" ] || continue
      mv "$d" "$HOME/.claude/projects/$new_enc${d##*/$old_enc}"
    done
  fi
  rewrite_home "$HOME"/.claude/plugins/*.json "$HOME/.claude/settings.json"

  python3 -I - "$SRC/claude/claude-json-extract.json" <<'EOF'
import json, os, sys
path = os.path.expanduser("~/.claude.json")
cur = json.load(open(path)) if os.path.exists(path) else {}
servers = cur.setdefault("mcpServers", {})
added = [k for k, v in json.load(open(sys.argv[1]))["mcpServers"].items() if servers.setdefault(k, v) is v]
json.dump(cur, open(path, "w"), indent=2)
print("  MCP servers added:", ", ".join(added) or "none")
EOF
}

restore_mem() {
  [ -d "$SRC/claude-mem" ] || { warn "no claude-mem snapshot, skipping"; return; }
  local pid_file="$HOME/.claude-mem/worker.pid"
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    warn "claude-mem worker is running (pid $(cat "$pid_file")). Quit all Claude sessions and stop it, then re-run: $0 mem"
    return 1
  fi
  log "claude-mem: restoring ~/.claude-mem"
  if [ -e "$HOME/.claude-mem" ]; then
    mv "$HOME/.claude-mem" "$HOME/.claude-mem.pre-restore-$TS"
    log "claude-mem: previous dir moved to ~/.claude-mem.pre-restore-$TS"
  fi
  rsync -a "$SRC/claude-mem/" "$HOME/.claude-mem/"
  rewrite_home "$HOME/.claude-mem/settings.json"
  log "claude-mem: $(sqlite3 "$HOME/.claude-mem/claude-mem.db" 'PRAGMA quick_check;')"
}

apply_worktree() {
  local repo="$1" dir="$2" n="$3" rel branch head target
  IFS=$'\t' read -r rel branch head < "$dir/wt-$n.meta"
  target="$HOME/$rel"
  if [ "$target" != "$repo" ] && [ ! -e "$target" ]; then
    mkdir -p "$(dirname "$target")"
    if [ "$branch" != "-" ]; then
      git -C "$repo" worktree add -q "$target" "$branch" || git -C "$repo" worktree add -q --detach "$target" "$head"
    else
      git -C "$repo" worktree add -q --detach "$target" "$head"
    fi
  fi
  if [ "$(git -C "$target" rev-parse HEAD)" != "$head" ] \
    || { [ -s "$dir/wt-$n.patch" ] && ! git -C "$target" apply --whitespace=nowarn "$dir/wt-$n.patch"; }; then
    mkdir -p "$repo/.git/migration"
    cp "$dir/wt-$n".* "$repo/.git/migration/"
    warn "$rel: dirty changes not applied, saved in $repo/.git/migration/wt-$n.patch (base $head)"
    return
  fi
  tar -C "$target" -xkzf "$dir/wt-$n.untracked.tgz" 2>/dev/null || true
}

replay_repo() {
  local repo="$1" dir="$2" branch="$3" b cur n idx sha msg
  if [ -f "$repo/.git/migration/.replayed" ]; then
    echo "    already replayed, skipping"
    return
  fi
  if [ -f "$dir/branches.bundle" ]; then
    git -C "$repo" fetch -q "$dir/branches.bundle" 'refs/heads/*:refs/remotes/migrated/*' 'refs/migrate/*:refs/migrate/*'
    cur="$(git -C "$repo" symbolic-ref --short -q HEAD || true)"
    git -C "$repo" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/migrated/ | while read -r b; do
      if ! git -C "$repo" show-ref -q --verify "refs/heads/$b"; then
        git -C "$repo" branch -q --no-track "$b" "migrated/$b"
      elif git -C "$repo" merge-base --is-ancestor "$b" "migrated/$b"; then
        if [ "$b" = "$cur" ]; then
          git -C "$repo" merge -q --ff-only "migrated/$b"
        else
          git -C "$repo" branch -q -f "$b" "migrated/$b"
        fi
      else
        warn "$repo: branch $b diverged from origin, migrated copy kept as migrated/$b"
        continue
      fi
      git -C "$repo" update-ref -d "refs/remotes/migrated/$b"
    done
  fi

  if [ "$branch" != "-" ] && [ "$(git -C "$repo" symbolic-ref --short -q HEAD || true)" != "$branch" ]; then
    git -C "$repo" checkout -q "$branch" 2>/dev/null || warn "$repo: could not check out $branch"
  fi

  for n in $(ls "$dir" 2>/dev/null | sed -n 's/^wt-\([0-9]*\)\.meta$/\1/p' | sort -n); do
    apply_worktree "$repo" "$dir" "$n"
  done

  if [ -f "$dir/stashes.tsv" ]; then
    awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }' "$dir/stashes.tsv" \
      | while IFS=$'\t' read -r idx sha msg; do
          git -C "$repo" stash store -m "$msg" "$sha"
        done
  fi

  git -C "$repo" for-each-ref --format='%(refname)' refs/migrate/ | while read -r b; do
    git -C "$repo" update-ref -d "$b"
  done
  mkdir -p "$repo/.git/migration"
  touch "$repo/.git/migration/.replayed"
}

restore_repos() {
  log "Repos: cloning (recent ${RECENT_DAYS}d$([ "$ALL_REPOS" = 1 ] && echo ', all'))"
  local cutoff rel url branch last has_bundle dirty repo dir skipped=0
  cutoff=$((EXPORTED_AT - RECENT_DAYS * 86400))
  while IFS=$'\t' read -r rel url branch last has_bundle dirty; do
    if [ "$ALL_REPOS" = 0 ] && [ "$has_bundle" = 0 ] && [ "$dirty" = 0 ] && [ "$last" -lt "$cutoff" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    repo="$HOME/$rel"
    dir="$SRC/repos/$(printf '%s' "$rel" | tr '/' '_')"
    if [ "$url" = "-" ]; then
      warn "$rel: no origin remote, copy it manually"
      continue
    fi
    if [ ! -d "$repo/.git" ]; then
      mkdir -p "$(dirname "$repo")"
      git clone -q "$url" "$repo" </dev/null || { warn "$rel: clone failed"; continue; }
    fi
    echo "  $rel"
    [ -d "$dir" ] && { replay_repo "$repo" "$dir" "$branch" </dev/null || warn "$rel: replay incomplete"; }
  done < "$SRC/repos.tsv"
  place_repo_files
  log "Repos: done ($skipped older repos skipped, use --all-repos to include them)"
}

restore_loose() {
  [ -d "$SRC/loose" ] || { warn "no loose files, skipping"; return; }
  log "Loose files: copying into ~/GitProjects"
  mkdir -p "$HOME/GitProjects"
  rsync -a --ignore-existing "$SRC/loose/" "$HOME/GitProjects/"
}

link_old_home() {
  [ "$OLD_HOME" = "$HOME" ] && return
  if [ -L "$OLD_HOME" ] || [ -e "$OLD_HOME" ]; then
    return
  fi
  log "Home changed ($OLD_HOME -> $HOME): linking old path so hardcoded references keep working (sudo)"
  sudo ln -s "$HOME" "$OLD_HOME" || warn "could not create $OLD_HOME symlink"
}

link_old_home
for step in "${STEPS[@]}"; do
  case "$step" in
    secrets) restore_secrets ;;
    claude) restore_claude ;;
    mem) restore_mem ;;
    repos) restore_repos ;;
    loose) restore_loose ;;
    *) warn "unknown step: $step"; usage; exit 1 ;;
  esac
done
log "Restore complete"
