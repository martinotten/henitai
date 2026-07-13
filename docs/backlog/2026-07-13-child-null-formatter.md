# Null RSpec Formatter in Mutant Children

Status: proposed
Date: 2026-07-13
Severity: Low (perf polish)
Source: rbspy flamegraph of a dogfood run (2026-07-13), taken after the
reporter-unparse and dependency-fingerprint fixes landed.

## Summary

With the parent-side hotspots eliminated, the remaining shaveable slice in
the profile is `RSpec::Core::Reporter` machinery **inside the mutant
children**: ~13% of total run samples spent on per-example progress
notifications whose output only lands in the per-mutant log files
(`reports/mutation-logs/`) and is never needed to classify the mutant —
kill/survive is decided by the child's exit status.

## Proposed Behavior

- In the forked mutant child (RSpec path: `RspecChildRunner`), configure a
  null/quiet formatter instead of the default progress formatter before
  `run_specs`, so per-example notification fan-out is skipped.
- Keep full output for the *baseline* run and for the coverage bootstrap
  suite run — those logs are user-facing diagnostics.
- Keep failure output available: on a survived-unexpectedly or debug case
  the log should still say which examples failed. Evaluate whether the
  failures-only summary (dump_failures/dump_summary) can stay while
  per-example `example_finished` fan-out goes; per-test coverage collection
  hooks (`RspecCoverageFormatter`) must remain wired in the bootstrap run
  but are already absent in children (coverage suppressed).
- Minitest child equivalent: check what reporter Minitest runs in-child and
  whether a ProgressReporter-less run is worth it there too.

## Expected Win

~5–10% of child wall time (13% of total samples were reporter frames;
some of that is unavoidable summary work). Worth doing opportunistically,
not urgent.

## Test Plan

- Unit: child runner configures the quiet formatter; baseline path
  unchanged.
- Smoke: `rake smoke:integration:all` — kills still detected, mutant logs
  still contain failure detail for killed mutants.
- Before/after flamegraph or timed dogfood subject run documenting the win.
