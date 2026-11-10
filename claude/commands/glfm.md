---
description: Fetch and merge origin/main into the current branch, resolving any conflicts
---

Bring the current branch up to date with `origin/main`. Steps:

1. Check the current branch and working-tree state:
   ```bash
   git status
   git rev-parse --abbrev-ref HEAD
   ```
   If `main`/`master`, stop and report — `glfm` is for feature branches.
2. If there are uncommitted changes, stash them: `git stash push -u -m "glfm-autostash"`. Remember to pop at the end.
3. Fetch the latest main:
   ```bash
   git fetch origin main
   ```
4. Merge `origin/main` into the current branch:
   ```bash
   git merge origin/main --no-edit
   ```
5. If merge conflicts occur:
   - Run `git status` to see conflicted files.
   - Resolve each conflict by reading both sides and reconciling intent. Prefer preserving the feature-branch work while honoring main's changes. Do NOT discard either side blindly with `git checkout --ours/--theirs` unless the file is truly trivial (lockfiles, generated files).
   - `git add` each resolved file.
   - Finish the merge with `git commit --no-edit` (the default merge commit message is fine).
6. If a stash was created in step 2, pop it: `git stash pop`. Resolve any conflicts the pop introduces the same way.
7. Run `val` to confirm the post-merge state still builds and tests pass.
8. Report: how many files conflicted, whether tests passed, and whether the branch is now ahead of `origin/main`.

Do NOT push. Do NOT force-push. Caller decides when to push.
