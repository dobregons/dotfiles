---
description: Review the current PR and fix every issue that is flagged
---

Run a thorough code review against the PR for the current branch, then fix every flagged issue. Steps:

1. Find the PR for the current branch:
   ```bash
   gh pr view --json url,number,headRefName,baseRefName,title
   ```
   If no PR exists, stop and report that — `prr` only runs against an open PR.
2. Fetch the base branch and compute the diff that the PR introduces:
   ```bash
   git fetch origin <base>
   git diff origin/<base>...HEAD
   ```
3. Review the diff for:
   - Correctness bugs, off-by-one, null/undefined handling, race conditions
   - Security: injection, XSS, SSRF, secrets in code, unsafe deserialization, missing authz
   - Error handling: unhandled rejections, swallowed errors, missing retries on flaky I/O
   - Tests: missing coverage for new branches, mocked-where-real-deps-matter
   - API/contract changes: backwards compatibility, schema drift, migration safety
   - Performance hot paths: N+1, unbounded loops, sync work in hot paths
   - Style/consistency vs surrounding code, dead code, leftover debug `console.log`
   - Type safety: `any`, `as` casts, suppressed errors
4. Filter to high-confidence, actionable issues. Skip nits and stylistic preferences that don't match an existing pattern in the repo.
5. For every remaining issue: fix it in code. Do not just leave a comment. Do not skip.
6. After fixes, run `val` to make sure validation still passes.
7. Commit the fixes with `gcp` (commit + push to existing branch).
8. Report a short summary: how many issues found, how many fixed, and any that were intentionally deferred (with reason).
