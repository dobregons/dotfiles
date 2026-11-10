---
description: Run repo validation (typecheck, lint, test) scoped to changed files. Fix anything broken.
---

Validate the current repo. Default to **path-aware scoping** so integration-heavy suites do not re-run for every task. Full validation is reserved for the PR boundary (handled by CI / `/gcpnb` / `/gcp`).

## Step 1 — Detect change scope

Compute the touched file set:

1. Determine the base ref. Default `origin/main`; if the current branch IS `main`, use `HEAD~1`. Fetch first: `git fetch origin main --quiet 2>/dev/null || true` (do not fail if offline).
2. Collect committed-diff files: `git diff --name-only "$BASE"...HEAD`.
3. Collect uncommitted files: `git status --porcelain | awk '{print $2}'` (handle renames `R  old -> new` — keep the new path).
4. Union both lists → `CHANGED_FILES`.
5. Derive `CHANGED_PACKAGES` for a monorepo: for each path matching `packages/<name>/...`, capture `<name>`. De-duplicate.
6. Classify the change:
   - **docs-only**: every path matches `\.(md|mdx|txt)$` OR lives under `docs/` / `CHANGELOG`.
   - **config-only**: every path matches lockfile / `*.json` / `*.yaml` / `*.toml` / `.github/` and no `.ts|.js|.tsx|.jsx|.go|.rs|.py` changed.
   - **code**: anything else.
   - **empty**: no changes → fall through to full validation (Step 4).

Print the classification + changed-package list before running anything.

## Step 2 — Detect runner scripts

Read `package.json` (or `Cargo.toml` / `go.mod` / `pyproject.toml` / `Makefile`). Identify these scripts if present: `type-check` (or `typecheck`), `lint`, `test`, `build`, `validate:ci`. Note the package manager (`npm` / `pnpm` / `yarn`) and whether the repo is a workspace monorepo (presence of `workspaces` field or `pnpm-workspace.yaml`).

## Step 3 — Scoped validation

Run in order. Stop only to fix failures. Do not skip, comment out, or weaken tests to make them pass.

### 3a. Type check — always full

Typecheck is fast vs integration tests and catches cross-package contract drift, so always run the repo-wide command (`npm run type-check` / `pnpm typecheck` / `tsc --noEmit`).

### 3b. Lint — scoped to changed files

If `CHANGED_FILES` contains lintable files (`.ts|.tsx|.js|.jsx|.mjs|.cjs`), pass them as args to the linter:

- npm/eslint: `npx eslint --fix <changed lintable files>`
- biome: `biome check --apply <files>`
- ruff: `ruff check --fix <files>`

If the repo has a `lint` script that accepts file args, prefer that. If the script hard-codes a glob with no override, fall back to `npx eslint --fix <files>` (or equivalent) to keep the scoping.

If `CHANGED_FILES` has zero lintable files, skip lint.

### 3c. Tests — scoped to changed packages

**Jest** (most common here):

- If `CHANGED_PACKAGES` is non-empty and the repo is a workspace: `npm test -- --testPathPattern="packages/(pkg1|pkg2)/"` (regex-join the package names).
- If `CHANGED_FILES` contains specific `*.test.ts` files, additionally pass them as positional args so they run for sure.
- Co-located source files imply running the test file with the same basename if it exists (Jest doesn't auto-discover that; pair source change with sibling test if `<file>.test.ts` exists).

**Other runners**:

- Vitest: `vitest run <changed pkg dirs>`
- Go: `go test ./packages/<pkg>/...` per changed package
- pytest: `pytest <touched test files>`
- Cargo: `cargo test -p <crate>` per changed crate

If classification is **docs-only**, skip tests entirely — print "skipping tests: docs-only change".

If `CHANGED_PACKAGES` is empty but `CHANGED_FILES` has code outside `packages/`, fall back to full `npm test`.

### 3d. Build — only if touched

Skip build unless a file under a `build`-script's input lives in `CHANGED_FILES`, or the change touches `tsconfig*.json` / `package.json` / build config. When skipped, print "skipping build: no build inputs changed".

## Step 4 — Full validation fallback

Run full `validate:ci` (or equivalent: type-check + lint + test + build all unfiltered) when ANY of:

- No changes detected (`CHANGED_FILES` empty).
- User invoked `/val full` (treat `full` arg as the override).
- Changes touch a shared-SDK / cross-cutting path: any of `packages/sdk/`, `packages/sdk-graph/`, `packages/config/`, `packages/test/`, root `tsconfig*.json`, root `package.json` `dependencies`/`devDependencies`. These have global blast radius — scoped tests miss regressions.

## Step 5 — Failure handling

For any failure: read the error, fix the root cause in code, re-run that step until clean. Never `--no-verify`, never disable rules inline, never delete failing tests.

## Step 6 — Report

Print: classification, what scope ran, what was skipped, what was fixed. If full fallback triggered, name the trigger. If everything was already green, say so.

Do not commit, push, or open a PR — `val` is validation only.
