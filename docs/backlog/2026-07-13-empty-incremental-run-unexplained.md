# Empty Incremental Run Prints Unexplained Zero Summary

Status: done
Date: 2026-07-13

## Resolution (2026-07-13)

`Result` now carries the run's `since:` ref; the terminal reporter appends
`No mutants: no configured source files changed since REF.` to the summary
when the result is empty and `since` is set (`Reporter::Terminal#empty_since_scope_line`).
Severity: Low (UX)
Source: field report — `henitai run --incremental --since origin/main` with
test-only changes printed `MS n/a | MSI n/a`, all counters 0, 0.13s, with no
explanation.

## Summary

When `--since` selects no subjects the terminal reporter prints the normal
summary block with every counter at zero and `n/a` scores. Nothing tells the
user *why* — was the ref wrong, were the changes test-only, did the includes
globs not match? Exit code is 0 (empty set cannot fail a threshold,
`run_command.rb`), so CI silently "passes".

## Proposed Behavior

- When the result contains zero mutants and the run was scoped with
  `--since REF`, the terminal summary states it explicitly, e.g.:
  `No mutants: no configured source files changed since REF.`
- Requires the reporter to know the run scope: thread `since` through
  `Result` (RBS update — `result.rb` is in the Steep scope).

## Test Plan

- Unit: terminal reporter emits the explanation line for an empty result
  built with a `since` ref, and omits it for a non-empty or unscoped result.
