# Laptop migration

## Old laptop

1. Commit and push `~/dotfiles`.
2. Quit every Claude Code session (lets claude-mem flush; the export snapshots sqlite safely either way).
3. Export to an external drive or any folder you can move:

   ```bash
   ~/dotfiles/migrate/export.sh --secrets /Volumes/<drive>/migration
   ```

   Pushing branches beats bundling them: anything you push now restores from GitHub instead.

## New laptop

Use the same macOS username if you can; otherwise `restore.sh` remaps `~/.claude/projects` and absolute paths.

```bash
xcode-select --install
git clone https://github.com/dobregons/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh

/Volumes/<drive>/migration/restore.sh secrets   # ssh, aws, kube, npm, tokens
/Volumes/<drive>/migration/restore.sh repos     # clone + replay local-only work
/Volumes/<drive>/migration/restore.sh claude mem loose
```

Restore `repos` before starting Claude: the `claude-toolbox` plugin marketplace is a local directory under `~/GitProjects`.
Start Claude only after `mem` (or stop its worker first), then run `claude` and accept the plugin install prompts.

Afterwards:

- `aws sso login`, `saml2aws login`, `gh auth status`, `op signin`
- `/claude-mem:cloud-sync` to confirm sync status
- `git branch -r | grep migrated/` shows branches that diverged and were not fast-forwarded
- `.git/migration/` in a repo holds any dirty-worktree patch that did not apply cleanly
- Git-ignored `.env` files are restored into each repo once it is cloned (from `secrets.dmg`)
- Personal LaunchAgents are restored but not started; `restore.sh secrets` prints the `launchctl bootstrap` command
- The old crontab is saved to `~/.migration-crontab` for review, not installed

To refresh only the secrets after a full export: `export.sh --secrets-only ~/migration`
