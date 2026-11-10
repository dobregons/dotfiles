#!/bin/bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--secrets] [--no-loose] [OUT_DIR]

Snapshot this Mac for restore.sh on a new one:
  repos       unpushed branches, stashes and dirty worktrees as git bundles + patches
  loose       non-repo files under ~/GitProjects (skip with --no-loose)
  claude      ~/.claude (transcripts, memory, history, plugins) minus caches
  claude-mem  ~/.claude-mem with a consistent sqlite snapshot
  secrets     ssh/aws/kube/npm/etc in an AES-256 encrypted DMG (only with --secrets)

OUT_DIR defaults to ~/Desktop/migration-YYYYMMDD
EOF
}

OUT=""
WITH_SECRETS=0
WITH_LOOSE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --secrets) WITH_SECRETS=1 ;;
    --no-loose) WITH_LOOSE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) OUT="$1" ;;
  esac
  shift
done
OUT="${OUT:-$HOME/Desktop/migration-$(date +%Y%m%d)}"
PROJECTS="$HOME/GitProjects"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cp "$HERE/restore.sh" "$HERE/README.md" "$OUT/"
chmod +x "$OUT/restore.sh"
printf 'OLD_HOME=%q\nEXPORTED_AT=%s\n' "$HOME" "$(date +%s)" > "$OUT/manifest.env"

repo_key() { printf '%s' "$1" | tr '/' '_'; }

base_ref() {
  local r
  for r in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
    if git -C "$1" rev-parse -q --verify "$r" >/dev/null; then
      echo "$r"
      return
    fi
  done
}

MAX_UNTRACKED_BYTES=$((25 * 1024 * 1024))

untracked_files() {
  local wt="$1" other d specs=()
  shift
  for other in "$@"; do
    case "$other" in "$wt"/*) specs+=(":(exclude)${other#$wt/}") ;; esac
  done
  for d in node_modules dist build .next .turbo coverage .venv __pycache__ target .worktrees .claude/worktrees; do
    specs+=(":(exclude,glob)**/$d/**" ":(exclude)$d")
  done
  git -C "$wt" ls-files --others --exclude-standard -z -- . "${specs[@]}" \
    | while IFS= read -r -d '' f; do
        if [ "$(stat -f %z "$wt/$f" 2>/dev/null || echo 0)" -gt "$MAX_UNTRACKED_BYTES" ]; then
          warn "skipped large untracked file: ${wt#$HOME/}/$f"
        else
          printf '%s\0' "$f"
        fi
      done
}

export_worktrees() {
  local repo="$1" dest="$2" n=0 path="" branch="-" head="" line list
  local all=()
  while IFS= read -r line; do
    all+=("$line")
  done < <(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')
  list="$(mktemp)"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "HEAD "*) head="${line#HEAD }" ;;
      "branch "*) branch="${line#branch refs/heads/}" ;;
      "")
        if [ -n "$path" ] && [ -d "$path" ]; then
          untracked_files "$path" "${all[@]}" > "$list"
          if [ -s "$list" ] || ! git -C "$path" diff HEAD --quiet 2>/dev/null; then
            n=$((n + 1))
            mkdir -p "$dest"
            git -C "$path" diff HEAD --binary > "$dest/wt-$n.patch"
            (cd "$path" && tar --null -T "$list" -czf "$dest/wt-$n.untracked.tgz")
            printf '%s\t%s\t%s\n' "${path#$HOME/}" "$branch" "$head" > "$dest/wt-$n.meta"
            git -C "$repo" update-ref "refs/migrate/wt-$n" "$head"
          fi
        fi
        path="" branch="-" head=""
        ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain; echo)
  rm -f "$list"
  echo "$n"
}

export_repo() {
  local repo="$1" rel key dest url branch last base stashes dirty count i sha msg
  rel="${repo#$HOME/}"
  key="$(repo_key "$rel")"
  dest="$OUT/repos/$key"
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || echo -)"
  branch="$(git -C "$repo" symbolic-ref --short -q HEAD || echo -)"
  last="$(stat -f %m "$repo/.git/index" 2>/dev/null || stat -f %m "$repo/.git")"

  dirty="$(export_worktrees "$repo" "$dest")"

  stashes=0
  i=0
  while IFS=$'\t' read -r sha msg; do
    [ -n "$sha" ] || continue
    mkdir -p "$dest"
    git -C "$repo" update-ref "refs/migrate/stash-$i" "$sha"
    printf '%s\t%s\t%s\n' "$i" "$sha" "$msg" >> "$dest/stashes.tsv"
    i=$((i + 1))
  done < <(git -C "$repo" stash list --format='%H%x09%gs' 2>/dev/null || true)
  stashes=$i

  base="$(base_ref "$repo")"
  count="$(git -C "$repo" rev-list --count --branches '--glob=refs/migrate/*' ${base:+--not "$base"} 2>/dev/null || echo 0)"
  local has_bundle=0
  if [ "$count" -gt 0 ]; then
    mkdir -p "$dest"
    git -C "$repo" bundle create -q "$dest/branches.bundle" --branches '--glob=refs/migrate/*' ${base:+--not "$base"} || warn "bundle failed: $rel"
    has_bundle=1
  fi
  git -C "$repo" for-each-ref --format='%(refname)' refs/migrate/ | while read -r ref; do
    git -C "$repo" update-ref -d "$ref"
  done

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$url" "$branch" "$last" "$has_bundle" "$dirty" >> "$OUT/repos.tsv"
  if [ "$has_bundle" = 1 ] || [ "$dirty" -gt 0 ]; then
    printf '  %-55s commits=%-4s stashes=%-3s dirty-worktrees=%s\n' "$rel" "$count" "$stashes" "$dirty"
  fi
}

discover_repos() {
  find "$PROJECTS" -maxdepth 3 -type d -name .git -not -path '*/node_modules/*' -prune 2>/dev/null | sed 's|/\.git$||' | sort
  if [ -d "$HOME/.config/nvim/.git" ]; then
    echo "$HOME/.config/nvim"
  fi
}

export_repos() {
  log "Repos: bundling unpushed work, stashes and dirty worktrees"
  rm -rf "$OUT/repos" "$OUT/repos.tsv"
  mkdir -p "$OUT/repos"
  discover_repos | while read -r repo; do
    export_repo "$repo" || warn "failed: $repo"
  done
  log "Repos: $(wc -l < "$OUT/repos.tsv" | tr -d ' ') recorded, $(ls "$OUT/repos" | wc -l | tr -d ' ') with local-only work"
}

export_loose() {
  log "Loose files: non-repo content under ~/GitProjects"
  local excludes
  excludes="$(mktemp)"
  {
    discover_repos | sed -n "s|^$PROJECTS||p" | sed 's|$|/|'
    find "$PROJECTS" -maxdepth 3 -type f -name .git -not -path '*/node_modules/*' 2>/dev/null \
      | sed "s|^$PROJECTS||; s|/\.git$|/|"
    printf '%s\n' node_modules/ .next/ .turbo/ dist/ build/ coverage/ .venv/ __pycache__/ target/ .DS_Store
  } > "$excludes"
  rsync -a --prune-empty-dirs --exclude-from="$excludes" "$PROJECTS/" "$OUT/loose/"
  rm -f "$excludes"
  log "Loose files: $(du -sh "$OUT/loose" | cut -f1)"
}

export_claude() {
  log "Claude: ~/.claude minus caches and dotfiles-managed files"
  rsync -a --delete \
    --exclude /CLAUDE.md --exclude /commands --exclude /agents --exclude /skills \
    --exclude /statusline-command.sh \
    --exclude /plugins/cache/ --exclude '/plugins/*cache*.json' \
    --exclude /cache/ --exclude /debug/ --exclude /telemetry/ --exclude /shell-snapshots/ \
    --exclude /session-env/ --exclude /sessions/ --exclude /ide/ --exclude /paste-cache/ \
    --exclude '/daemon*' --exclude '/policy-limits*' --exclude /remote-settings.json \
    --exclude /mcp-needs-auth-cache.json --exclude /gh-pr-status-cache.json --exclude /stats-cache.json \
    "$HOME/.claude/" "$OUT/claude/"

  python3 -I - "$HOME" "$OUT/claude" <<'EOF'
import json, os, shutil, sys
home, out = sys.argv[1], sys.argv[2]
installed = json.load(open(os.path.join(home, ".claude/plugins/installed_plugins.json")))
for entries in installed["plugins"].values():
    for e in entries:
        src = e["installPath"]
        if os.path.isdir(src):
            dst = os.path.join(out, os.path.relpath(src, os.path.join(home, ".claude")))
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst, symlinks=True)
cfg = json.load(open(os.path.join(home, ".claude.json")))
json.dump({"mcpServers": cfg.get("mcpServers", {})}, open(os.path.join(out, "claude-json-extract.json"), "w"), indent=2)
EOF
  log "Claude: $(du -sh "$OUT/claude" | cut -f1)"
}

export_claude_mem() {
  log "claude-mem: sqlite snapshot + chroma index"
  local src="$HOME/.claude-mem" db
  [ -d "$src" ] || { warn "no ~/.claude-mem"; return; }
  mkdir -p "$OUT/claude-mem"
  rsync -a --delete \
    --exclude /logs/ --exclude /run/ --exclude /worker.pid --exclude /worker-heartbeat.json \
    --exclude /observer-health.json --exclude '/*.db' --exclude '/*.db-wal' --exclude '/*.db-shm' \
    "$src/" "$OUT/claude-mem/"
  for db in "$src"/*.db; do
    sqlite3 "$db" ".backup '$OUT/claude-mem/$(basename "$db")'"
    printf '  %s integrity: %s\n' "$(basename "$db")" "$(sqlite3 "$OUT/claude-mem/$(basename "$db")" 'PRAGMA quick_check;')"
  done
  log "claude-mem: $(du -sh "$OUT/claude-mem" | cut -f1)"
}

export_secrets() {
  log "Secrets: building encrypted DMG"
  local staging items=() f pw pw2
  for f in .ssh .aws .saml2aws .npmrc .yarnrc .netrc .kube .zshrc.local .j1dev-api-key .nr_key \
           .docker/config.json .config/gh/hosts.yml .terraform.d/credentials.tfrc.json; do
    [ -e "$HOME/$f" ] && items+=("$f")
  done
  staging="$(mktemp -d)"
  chmod 700 "$staging"
  tar -C "$HOME" -cHf - \
    --exclude '.aws/cli/cache' --exclude '.aws/sso/cache' --exclude '.DS_Store' \
    --exclude '.kube/cache' --exclude '.kube/http-cache' \
    "${items[@]}" | tar -C "$staging" -xpf -
  printf '  included: %s\n' "${items[*]}"

  while :; do
    read -rsp "  DMG password: " pw; echo
    read -rsp "  Repeat: " pw2; echo
    [ -n "$pw" ] && [ "$pw" = "$pw2" ] && break
    warn "passwords empty or do not match"
  done
  rm -f "$OUT/secrets.dmg"
  printf '%s' "$pw" | hdiutil create -quiet -encryption AES-256 -stdinpass \
    -volname migration-secrets -srcfolder "$staging" -format UDZO "$OUT/secrets.dmg"
  rm -rf "$staging"
  log "Secrets: $OUT/secrets.dmg"
}

export_repos
[ "$WITH_LOOSE" = 1 ] && export_loose
export_claude
export_claude_mem
if [ "$WITH_SECRETS" = 1 ]; then
  export_secrets
else
  warn "secrets skipped (re-run with --secrets to build the encrypted DMG)"
fi

log "Done: $OUT"
du -sh "$OUT"/* | sed 's/^/  /'
