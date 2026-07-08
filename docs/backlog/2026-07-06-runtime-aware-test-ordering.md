# Runtime-Aware Test Ordering (Fastest-First Tiebreaker)

Status: done (2026-07-08)
Date: 2026-07-06
Severity: Low
Source: cross-framework comparison — PIT 1.25 (coverage + test timings,
fastest-first), Infection 0.34 (`TestLocationBucketSorter`, bucket sort on
JUnit timings), mutmut 3.6 (covering tests "sorted by time") — see
`docs/research/cross_framework_comparison.md` §2.2

## Summary

Every reviewed framework with per-test selection orders the selected tests
fastest-first, so a mutant's first kill costs as little wall-clock as
possible. Henitai's `TestPrioritizer` (`lib/henitai/test_prioritizer.rb`)
orders by kill-history count only; among tests with equal history (the common
case: 0 for every new mutant), original inventory order decides — which is
arbitrary with respect to cost.

## Problem

`TestPrioritizer#sort` sorts by `[-history_count, index]`. For a fresh run,
`history_count` is 0 across the board and the tiebreaker is inventory order.
If the first candidate happens to be a slow integration spec and the third a
fast unit spec that also kills the mutant, the run pays the slow spec's full
runtime for every such mutant. PIT's design (coverage picks *which*, timing
picks *in what order*) shows the two heuristics compose.

## Proposed Behavior

- Keep kill-history as the primary key (it is a stronger signal than speed:
  a test that killed this mutant's neighbors probably kills this one).
- Replace the index tiebreaker with measured per-test-file runtime,
  ascending: `[-history_count, runtime, index]`.
- Runtime source: per-test timing captured during the coverage bootstrap run
  (Gate 0) — the same measurement point the auto-calibrated-timeout ticket
  (`2026-07-02-auto-calibrated-timeout.md`) needs. Implement the shared
  timing capture once; both consumers read it.
- Missing timing data (warm-coverage runs where bootstrap didn't execute,
  see the timeout ticket's open question) degrades gracefully to today's
  behavior (index tiebreaker).

## Non-Goals

- Not reordering by predicted kill probability models — history count stays
  the primary signal.
- Not per-example timing — per-test-file granularity matches what
  `PerTestCoverageSelector` selects.

## Open Questions

- Where to persist timings: extend `henitai_per_test.json` (already
  per-test-file, already propagated to forked children via
  `HENITAI_REPORTS_DIR`) vs. a new sidecar file. Leaning: extend the
  existing report — one artifact, one reader (`CoverageReportReader`).
- Shared design with auto-calibrated timeout: both tickets need Gate 0
  timing capture. Whichever lands first builds the capture; sequence them
  deliberately rather than implementing twice.

## Implementation Notes

- `lib/henitai/test_prioritizer.rb#sort` — add the runtime key; constructor
  gains an injected timing source (same collaborator-injection style as
  `PerTestCoverageSelector`'s `coverage_report_reader`).
- `lib/henitai/per_test_coverage_collector.rb` — capture wall-clock per test
  file alongside line coverage.
- `lib/henitai/coverage_report_reader.rb` — expose timings.
- Specs: `spec/henitai/test_prioritizer_spec.rb` (equal-history ordering by
  runtime; missing-timing fallback to index), collector/reader specs for the
  new field.

## Fix Plan (TDD)

Phase 1 (timing capture) is shared with
[[2026-07-02-auto-calibrated-timeout]] — if that ticket landed first,
skip to step 4.

1. **Red.** `per_test_coverage_collector_spec.rb`: collected data carries
   a wall-clock `duration` (float, seconds) per test file alongside line
   coverage; serialized into `henitai_per_test.json`.
2. **Red.** `coverage_report_reader_spec.rb`: `durations_by_test(path)`
   returns the map; legacy files without the field return `{}` (no raise —
   backward compat).
3. **Green** both.
4. **Red.** `test_prioritizer_spec.rb`: constructor accepts an injected
   timing source (same DI style as `PerTestCoverageSelector`'s
   `coverage_report_reader`). Matrix:
   - equal history counts → ascending runtime order
   - unequal history → history dominates regardless of runtime
   - timing missing for some tests → those sort after timed ones by
     original index (deterministic)
   - timing source empty/unavailable → exact current behavior
     (`[-history, index]`), proven by running the existing examples
     unmodified against the new constructor default.
5. **Green.** Sort key becomes `[-history_count, runtime_or_infinity,
   index]`.
6. **Red.** `execution_engine_spec.rb`: the prioritizer built in
   `test_prioritizer` receives the timing source wired from the reports
   dir (composition-root change only).
7. **Green**, refactor, rubocop, steep, full suite.

## Acceptance

- Tests with equal kill-history run in ascending measured-runtime order.
- Kill-history remains the dominant key (a slower test with more kills
  still runs first).
- Missing/partial/absent timing data degrades deterministically to
  today's ordering; zero existing prioritizer examples modified.
- Legacy `henitai_per_test.json` files (no `duration` field) load without
  error.
- No new CLI or config surface (pure internal improvement).

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | prioritizer matrix (4 cases above) + existing examples green unmodified |
| Unit | collector duration capture; reader accessor + legacy-file compat |
| Unit | engine composition: timing source reaches the prioritizer |
| Smoke | rspec fixture: after a run, `henitai_per_test.json` contains `duration` per test file |
| Regression | full dogfood run — status distribution unchanged (ordering affects wall-clock, never verdicts) |
