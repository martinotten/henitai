# Test-Aware Incremental Selection (Changed Test -> Covered Subjects)

Status: done
Date: 2026-07-13

## Resolution (2026-07-13)

File-level expansion shipped: `Runner#covered_sources_for_changed_tests`
maps each changed path through the new
`PerTestCoverage#source_files_covered_by` (previous run's
`henitai_per_test.json`) and unions the covered source files into the
`--since` changed set. First run without a map: no expansion, as proposed.
Line-level intersection remains a possible later refinement (not filed).
Severity: Medium (feature gap vs Stryker incremental)
Source: field report — editing only a test file under
`--incremental --since origin/main` selects zero subjects, so the new
assertion's killing power is never measured.

## Summary

`Runner#filter_changed` intersects the changed-file set with the configured
source globs; test files never pass that filter and contribute nothing. A new
or edited test is exactly the event that can kill previous survivors —
Stryker's incremental mode re-tests mutants covered by changed tests for this
reason. Henitai already records the needed mapping: the per-test coverage
report (`henitai_per_test.json`) maps each test file to the source files and
lines it reaches. Shipped verdict reuse (ADR-11) already *invalidates*
Survived verdicts when covering tests change, but only for mutants that were
selected in the first place — under `--since` they never are.

## Proposed Behavior

- During `--since` selection, changed files that appear as test keys in the
  per-test coverage map expand to the source files that test covers; those
  sources join the changed set (file-level, matching the existing file-level
  `--since` granularity).
- Uses the per-test map from the previous run (Gate 1 runs before the Gate 0
  bootstrap finishes). First run without a map: no expansion — acceptable,
  as a first run has no history to be incremental against.
- Later refinement (separate ticket if wanted): line-level intersection so a
  changed test only re-tests subjects whose ranges it actually covers.

## Test Plan

- Unit: changed test file (per stubbed diff) plus a per-test map covering
  `lib/foo.rb` selects `lib/foo.rb`'s subjects.
- Unit: changed test file with no per-test map selects nothing extra.
- Unit: path normalization — relative git paths vs absolute map keys.
