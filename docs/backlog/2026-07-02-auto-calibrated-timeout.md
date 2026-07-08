# Auto-Calibrated Mutant Timeout

Status: done (2026-07-08)
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `mutant` and `cargo-mutants`;
evidence extended 2026-07-06 by the cross-framework round
(`docs/research/cross_framework_comparison.md` §2.3)

## Summary

`cargo-mutants` derives its per-mutant timeout automatically from a measured
baseline test run (`5× baseline time, minimum 20s`), so it self-adjusts to
project speed. Henitai's `timeout:` (`.henitai.yml` `mutation.timeout`,
`lib/henitai/configuration.rb`) is a single fixed value the user must guess
and maintain by hand.

## Problem

`Configuration#timeout` (`lib/henitai/configuration.rb:87`) reads
`mutation[:timeout] || DEFAULT_TIMEOUT` — a flat number applied to every
mutant execution via `ExecutionEngine#run_with_flaky_retry`
(`config.timeout` passed straight into `integration.run_mutant`). This value
has no relationship to how long the relevant test subset actually takes:

- Too low: legitimate infinite-loop-inducing mutants get killed via timeout
  correctly, but so do mutants covered by a slower-than-average test subset,
  inflating `Timeout` counts and (depending on `coverage_criteria.timeout`)
  either falsely counting as kills or falsely counting as failures to
  investigate.
- Too high: every genuinely-hanging mutant now blocks a worker slot for
  much longer than necessary, directly increasing wall-clock cost — the
  thing this whole tool is trying to minimize.
- The value has to be re-tuned by hand as the suite grows or shrinks, and
  differs per-subject in ways a single global number can't capture (a
  method covered by 3 fast unit tests vs. one covered by a slow integration
  test needs a different timeout).

## Cross-Framework Evidence (added 2026-07-06)

Baseline-derived timeouts are industry consensus, not a cargo-mutants
quirk — four independent implementations (live-verified 2026-07-06):

- **cargo-mutants**: `5× baseline, min 20s` (original evidence).
- **StrykerJS 9.6**: `netTime × timeoutFactor(1.5) + timeoutMS(5000) +
  overheadMs`.
- **PIT 1.25**: `observed test runtime × timeoutFactor(1.25) +
  timeoutConstant(4000ms)` — notably PIT measures *per selected test*, which
  matches this ticket's per-mutant-baseline preference.
- **mutmut 3.6**: `(estimated_time_of_tests + timeout_constant(15)) ×
  timeout_multiplier(1.0)` **plus a separate CPU-time limit ~2× the wall
  limit enforced via SIGXCPU then SIGKILL** — the CPU-limit idea catches
  busy-loop mutants even when wall-clock is inflated by slow I/O and is
  worth considering as a second guard here.

Only Infection (and henitai) still use a fixed manual value. The severity
of this ticket was set from single-framework evidence; the 4-way consensus
is an argument to re-rank it upward when the backlog is next prioritized.

## Proposed Behavior

- During Gate 0 (coverage bootstrap, `CoverageBootstrapper#ensure!`), which
  already runs the relevant suite once, record the wall-clock duration.
- Derive a default timeout as a multiplier of a *relevant* baseline —
  ideally per-mutant (the actual `test_files` subset selected by
  `PerTestCoverageSelector`/`TestPrioritizer` for that mutant), not one
  global number, since henitai already does per-mutant test selection
  unlike `cargo-mutants`' whole-suite-per-mutant model.
- Keep `mutation.timeout` in `.henitai.yml` as an explicit override — if
  set, skip calibration entirely (fixed value wins, as today).
- Provide a floor (e.g. `2.0s`) so a near-instant single-test baseline
  doesn't produce an unreasonably tight timeout that flags normal jitter as
  a timeout.

## Suggested Interface

No new CLI flag needed for the default path. Optional:
`henitai run --timeout-multiplier N` to override the default multiplier
without hand-computing an absolute value.

## Non-Goals

- Not replacing the existing fixed-`timeout:` override — auto-calibration
  is the *default* when unset, not the only mode.
- Not solving flaky-retry timing (`config.max_flaky_retries`) — orthogonal,
  already handled separately.

## Open Questions

- Per-mutant baseline (measured from the coverage-bootstrap run's per-test
  timing data, if available) vs. one global baseline (simpler, cheaper,
  closer to what `cargo-mutants` does) — per-mutant is more accurate but
  needs per-test timing data that coverage bootstrap doesn't currently
  capture; needs a small design spike before committing to an approach.
- Default multiplier value — `cargo-mutants` uses `5×`; needs empirical
  tuning against this repo's own dogfood suite before picking a default.
- Interaction with `coverage_criteria.timeout` (whether a timeout counts as
  a kill) — a bad calibration could shift mutation-score numbers even
  though nothing in the source changed; needs a regression check against
  `mutation-history.sqlite3` trend data before/after enabling.
- **No baseline on warm-coverage runs.** `CoverageBootstrapper#ensure!`
  only runs the suite when existing coverage is missing/stale
  (`coverage_ready?` check) — on the common case of a repeat local run
  with fresh coverage already on disk, bootstrap does *not* run the suite
  at all, so there's no baseline timing to calibrate from. Needs a
  fallback: reuse the last bootstrap's recorded timing (persisted
  somewhere across runs), fall back to the static `DEFAULT_TIMEOUT`, or
  force a lightweight timing-only run independent of the coverage-ready
  check. Not yet decided.

## Implementation Notes

- `lib/henitai/coverage_bootstrapper.rb` is the natural place to capture
  baseline timing since it already runs the suite once per bootstrap (see
  the Open Question above on what happens when it doesn't run).
- `lib/henitai/execution_engine.rb#run_with_flaky_retry` — the actual
  `config.timeout` consumption point (passed into `integration.run_mutant`)
  — is what would need the calibrated value instead of (or as a fallback
  default for) the static config value.

## Fix Plan (TDD)

Phase 1 is shared infrastructure with
[[2026-07-06-runtime-aware-test-ordering]] — implement once, both tickets
consume it. Whichever ticket lands first builds Phase 1.

**Phase 1 — Gate-0 timing capture (shared):**

1. **Red.** Spec for `PerTestCoverageCollector`: after a collected run,
   each test file entry carries a wall-clock `duration` (seconds, float)
   alongside its line coverage. Spec for `CoverageReportReader`: exposes
   `durations_by_test(path)`; returns `{}` for legacy files without the
   field (backward compat — old `henitai_per_test.json` must stay
   readable).
2. **Green.** Capture per-test-file wall time in the collector, serialize
   into `henitai_per_test.json`; reader accessor.

**Phase 2 — calibration:**

3. **Red.** Spec for a new `TimeoutCalibrator` (pure object, injected
   timing source): given the selected test files for a mutant and their
   durations, returns `multiplier × sum(durations)` clamped to a floor
   (2.0s). Matrix: timings present / partially present (missing file →
   treat run as uncalibratable, fall back) / absent entirely (→ nil,
   caller falls back to `DEFAULT_TIMEOUT`).
4. **Green.** Implement calibrator.
5. **Red.** Spec for `ExecutionEngine`: when `mutation.timeout` is unset
   in config, `integration.run_mutant` receives the calibrated value for
   that mutant's test subset; when set, it receives the config value
   untouched (fixed override wins); when calibration returns nil, it
   receives `DEFAULT_TIMEOUT` and exactly one warning is emitted per run
   (not per mutant).
6. **Green.** Wire calibrator into the engine seam.
7. **Red.** Config/CLI: `mutation.timeout_multiplier` key (default 3.0,
   pending empirical tuning) + `--timeout-multiplier` flag; validator +
   `assets/schema/henitai.schema.json` entry;
   `spec/infra/config schema` invariants stay green.
8. **Green**, refactor, full suite.

## Acceptance

- `mutation.timeout` set: behavior byte-identical to today (existing
  timeout specs pass unmodified).
- `mutation.timeout` unset + timing data present: per-mutant timeout is
  `multiplier × baseline(selected tests)`, never below the 2.0s floor,
  deterministic given the timing file.
- No timing data (warm-coverage run, no persisted baseline):
  `DEFAULT_TIMEOUT` fallback + one warning line naming the fallback cause.
- Regression guard: dogfood run before/after on unchanged source produces
  identical mutant statuses (checked against
  `mutation-history.sqlite3` trend — no score drift from calibration
  alone).
- RuboCop, Steep, full suite green.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | `timeout_calibrator_spec.rb` (full matrix incl. floor + fallbacks); collector/reader specs for the `duration` field + legacy-file compat |
| Unit | `execution_engine_spec.rb`: calibrated vs fixed vs fallback value reaches `integration.run_mutant`; single-warning behavior |
| Config | validator + schema specs for `timeout_multiplier`; CLI option parsing spec |
| Smoke | rspec fixture: first run writes durations into `henitai_per_test.json` (assert field present); second run with `timeout:` removed from fixture config completes with calibrated timeouts (assert via `--all-logs` output marker) |
| Regression | full dogfood `bundle exec henitai run` — status distribution unchanged vs prior run |
