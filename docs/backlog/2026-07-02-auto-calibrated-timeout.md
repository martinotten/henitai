# Auto-Calibrated Mutant Timeout

Status: backlog
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `mutant` and `cargo-mutants`

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
