# `runner_spec` Uses `send` to Reach Private Runner Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/runner_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/runner_spec.rb)
uses `send` for runner internals such as path normalization, threshold
resolution, and dirty-source detection.

## Problem

- The file heavily exercises private helpers instead of the public runner flow.
- This makes it fragile against refactors in the orchestration layer.

## Fix Sketch

- Prefer end-to-end runner scenarios through `run`.
- Keep a minimal set of helper tests only if they are truly necessary.

## Test Plan

- Remove or reduce `send` calls by testing the public runner outcomes.
- Preserve only behavior that is externally visible to callers.

## Convention Note (added 2026-08-21)

The Fix Sketch above says to shift coverage to the public entry points. That
prescription is **superseded**: see
[`2026-07-08-review-send-integration-minitest-spec.md`](2026-07-08-review-send-integration-minitest-spec.md),
the one ticket in this family that was actually resolved. It extracted public
collaborators instead, and took `Henitai::Integration::Minitest` from
MS 72.83% / MSI 43.05% to MS 100% / MSI 91.87%.

This repository scores mutation coverage against itself, so a pure public-API
rewrite usually *loses* coverage — the assertions end up further from the logic
they constrain. Extract a public collaborator; rewrite in place only where a
public path genuinely reaches the behavior.

The budget for this file in `spec/infra/private_method_reach_spec.rb` must come
down in the same commit as any reduction here.

## Resolution (2026-08-21)

Reach dropped 24 -> 11 across four extractions. The residue is deliberate.

**`DirtySourceDetector`** (`lib/henitai/dirty_source_detector.rb`). The five
`strategy.send(:dirty_source_files?, ...)` calls were testing
`SurvivorRerunStrategy`, not `Runner` at all — a misplacement, not just private
reach. `#dirty?(worktree_files, git_sha:)` now owns the committed-versus-worktree
change sets, include-root matching and the conservative
`rescue StandardError => true`.

**`SourceFileSelection`** and **`SubjectSelection`**. Together these took ~45
lines and eleven private methods out of `Runner`, plus eight RBS declarations.
The two rules that had been reachable only by `send` — the working tree counts
as "changed since REF", and a changed test file pulls in the sources it covers —
now have direct coverage.

**`RunnerDependencies`** (`lib/henitai/runner_dependencies.rb`). `Runner`
gained a `deps:` seam, assigned in the body after `@config` because a keyword
default cannot reference it and `config:` itself defaults to
`Configuration.load`. `Runner`'s thirteen memoized private readers became
one-line delegators.

This is where coverage rose most. `CompositeProgressReporter.for`'s four-way
branch (terminal / composite / lone checkpoint / nil) previously had no seam
except `runner.send(:progress_reporter)`; it now has a dedicated spec, as does
`source_provider`'s caching lambda with its `rescue => ""`. Memoization itself
is asserted, because for `per_test_coverage` and `history_store` it is a
correctness requirement rather than an optimisation: the incremental filter
proves survivor reuse against the same live coverage map the history store
records its intersection set from.

### Two specs had to be strengthened after falsification

- The `progress_reporter` "passes `full_run` through on every call" example was
  vacuous with a nil-returning stub, because an `||=` memoization re-evaluates
  on nil anyway. It now stubs a truthy reporter, so memoizing that method
  genuinely fails the example.
- `source_provider` is deliberately *not* memoized, matching the original: each
  call gets its own cache, scoped to one reporter's lifetime. That is now
  asserted in both directions — content is cached within one lambda, and a
  second lambda sees fresh content.

### Residue (11)

`resolve_subjects` x2, `mutants_for` x2, `safe_head_sha` x2,
`result_thresholds` x2, `survivor_strategy` x1, `report` x1,
`git_diff_analyzer` x1.

These are the plan's step 4.6b dry-run conversions: each is reachable through
`#run` with the existing dry-run harness (`stub_dry_run_pipeline` plus a stubbed
`ReportsDirectoryLock`) and asserted via `result.thresholds` / `result.git_sha`
/ `result.mutants` instead. Not done here — a dry-run round trip is a weaker,
more indirect assertion than the direct call, and unlike the extractions above
it buys no new collaborator coverage. Filed as follow-up rather than forced.
