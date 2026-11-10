---
description: Create a new branch from main, commit changes, push, and open a PR
---

Create a fresh branch from `main`, commit the current working-tree changes onto it, push, and open a pull request. Steps:

1. Run `git status` and `git diff` to understand the changes and check that you're on a clean base (or that uncommitted changes are the intended ones).
2. Make sure local `main` is up to date: `git fetch origin main`.
3. Pick a short, descriptive branch name in kebab-case (e.g. `fix-auth-token-expiry`, `add-storybook-stories`). If `$ARGUMENTS` is provided, use it as the branch name.
4. Create and switch to the new branch from `origin/main`:
   ```bash
   git checkout -b <branch-name> origin/main
   ```
5. Stage relevant files explicitly with `git add <file> …`. Never `git add -A` / `git add .`.
6. Draft a Conventional Commits style message (`feat:`, `fix:`, `refactor:`, etc.). Subject ≤ 72 chars, imperative mood. Body only if the "why" isn't obvious.
7. Commit using a HEREDOC:
   ```bash
   git commit -m "$(cat <<'EOF'
   <subject>

   <optional body>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
8. Push with upstream: `git push -u origin <branch-name>`.
9. Open the PR with `gh pr create`, base `main`. Use a HEREDOC for the body:
   ```bash
   gh pr create --base main --title "<pr title>" --body "$(cat <<'EOF'
   ## Summary
   - <bullet 1>
   - <bullet 2>

   ## Test plan
   - [ ] <how to verify>

   🤖 Generated with Claude Code
   EOF
   )"
   ```
10. If a pre-commit hook fails, fix the root cause, re-stage, and create a NEW commit. Never use `--no-verify` or `--amend`.
11. Report the PR URL.
