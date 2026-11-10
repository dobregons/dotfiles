---
description: Stage all changes, generate a commit message from the diff, and push to the current branch
---

Commit and push the current changes on the existing branch. Steps:

1. Run `git status` and `git diff` (staged + unstaged) to understand what changed.
2. Stage relevant files with `git add` — name files explicitly. Do NOT use `git add -A` or `git add .` (avoid accidentally committing `.env`, credentials, large binaries, or unrelated junk).
3. Draft a Conventional Commits style message (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`). Subject ≤ 72 chars, imperative mood. Add a body only if the "why" isn't obvious from the subject.
4. Create the commit using a HEREDOC so formatting is preserved:
   ```bash
   git commit -m "$(cat <<'EOF'
   <subject>

   <optional body>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
5. Push with `git push`. If the branch has no upstream, use `git push -u origin <branch>`.
6. If a pre-commit hook fails, fix the underlying issue, re-stage, and create a NEW commit. Do not use `--no-verify` or `--amend`.
7. Report the commit SHA and branch.

Do NOT create a new branch. Do NOT open a PR. Use `gcpnb` for that.
