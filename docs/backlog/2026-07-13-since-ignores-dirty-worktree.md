# --since Ignores Uncommitted Working-Tree Changes

Status: done
Date: 2026-07-13

## Resolution (2026-07-13)

`Runner#changed_paths_since` now unions `changed_files(from: @since, to: "HEAD")`
with `working_tree_changed_files` (tracked dirty + untracked). No new flag.
Verified by dogfood: `henitai run --since HEAD --dry-run` with only dirty
lib files selects their subjects.
Severity: Medium (silent wrong scope during pre-commit dogfooding)
Source: field report — `henitai run --incremental --since origin/main` in a
Rails app returned 0 subjects while the working tree had uncommitted changes.

## Summary

`Runner#filter_changed` builds the changed-file set from
`GitDiffAnalyzer#changed_files(from: @since, to: "HEAD")` — a committed-range
diff. Uncommitted edits (tracked-dirty or untracked files) are invisible, so
the exact scenario `--since` exists for — "what did I change since main?"
asked before committing — silently under-selects. `GitDiffAnalyzer` already
has `working_tree_changed_files` (tracked-dirty vs HEAD plus untracked), but
only `SurvivorRerunStrategy` uses it.

## Proposed Behavior

- `--since REF` selects the union of: files changed in `REF..HEAD`, plus
  tracked files dirty vs HEAD, plus untracked files.
- No new flag: the working tree is what gets tested, so it is always part of
  "changed since REF".

## Test Plan

- Unit: `Runner#source_files` with `since:` includes a source file that is
  only dirty in the working tree (stub `GitDiffAnalyzer`).
- Unit: untracked new source file is selected.
- Existing committed-range behavior unchanged.
