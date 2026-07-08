# Repo Hygiene: gitignore Gaps and Working-Tree Cruft

Status: done
Date: 2026-06-16
Severity: Low
Source: 2026-06-16 structured review

## Summary

The working tree carries build/tool artifacts, and `.gitignore` misses the
graphify tool outputs. None of the stray `.gem`/coverage/report files are
tracked (good), but the clutter and one gitignore gap should be cleaned.

## Problem

- `graphify-out/`, `.graphify_semantic_targets.txt`, `.graphify_uncached.txt`
  are NOT covered by `.gitignore`. Risk of accidentally committing tool cache.
- Working tree holds 8 stray `*.gem` files (0.1.4–0.2.0), `coverage/`,
  `reports/` with logs and `Kopie`/`Kopie 2` duplicates, and `.DS_Store`.
  These ARE gitignored already, so they are untracked clutter, not committed —
  but should be removed locally.

## Fix Plan

1. **Patch `.gitignore`.** Add:
   ```
   graphify-out/
   .graphify_*
   ```
2. **Confirm nothing tracked.** Run `rtk git ls-files | rtk grep -E
   '\.gem$|^coverage/|^reports/|\.DS_Store|graphify'` — expect empty. If any
   appear, `git rm --cached` them.
3. **Clean working tree locally.** Remove the stray `*.gem` files, `coverage/`,
   the `reports/*Kopie*` duplicates, and `.DS_Store`. (Local cleanup only — none
   are tracked.)
4. **Document build hygiene.** Note in the release process that `gem build`
   output should not be left in the repo root (or build into a `pkg/` dir that
   is gitignored).

## Acceptance

- `.gitignore` covers graphify artifacts.
- `git ls-files` shows no gems, coverage, reports, or `.DS_Store`.
- Working tree free of stray build artifacts.

## Related

- [[2026-06-16-review-doc-debt]]
