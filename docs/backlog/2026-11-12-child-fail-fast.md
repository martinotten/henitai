# Fail-Fast Inside the Mutant Child

Status: proposed
Date: 2026-11-12
Severity: Medium (wall-clock per killed mutant)
Source: optimization research 2026-11-12 (PIT, Stryker and Infection all stop
a mutant's test run at the first failure)

## Summary

A mutant is `Killed` as soon as one selected test fails. Henitai's child
still runs every selected test file to completion: the RSpec child builds its
runner from empty `ConfigurationOptions` (no `fail_fast`), and the Minitest
child calls `Minitest.run([])` over all selected files. For a killed mutant
the time after the first failure is pure waste. Kill-history plus
fastest-first ordering (`TestPrioritizer`) already puts the likely killer
first, so stopping there captures most of the benefit of that ordering.

## Proposed Behavior

- RSpec child: set `fail_fast = 1` on the child's RSpec configuration, so the
  run stops after the first failing example.
- Minitest child: stop after the first test file whose outcome is a failure
  (Minitest has no built-in fail-fast; the outcome reporter that already
  records per-file outcomes can request the stop).
- Applies to the per-mutant child and to fork-server children alike.
- The baseline/coverage bootstrap run and `ControlRun` keep running the full
  selection (they need complete outcomes).

## Open Questions

- Flaky retry (`mutation.flaky_detection`): `MutantVerdict` retries a kill
  only when every file in `failed_tests` is flaky. With fail-fast,
  `failed_tests` holds just the first failing file. Retrying is still sound
  (the retry reruns the full mutant), but a retry now triggers more often
  when the first failing file is flaky and a later, non-flaky file would also
  have failed. Options: accept it, or disable fail-fast when the flaky set is
  non-empty. Leaning: accept, and document it.
- Opt-out switch (`mutation.fail_fast: false`) for debugging full child
  output? Leaning: no config until someone needs it; `--all-logs` already
  shows the failure.

## Fix Plan (TDD)

1. **Red.** RSpec child runner spec: the configured runner has
   `fail_fast == 1`.
2. **Green.** Set it in `configure_rspec_runner`
   (`lib/henitai/integration/rspec_child_runner.rb`).
3. **Red.** Minitest test runner spec: with two failing files selected, the
   second file's tests do not run; the recorded outcome lists only the first
   failing file.
4. **Green.** Stop request from the outcome reporter
   (`lib/henitai/integration/minitest_outcome_reporter.rb`,
   `minitest_test_runner.rb`).
5. **Red/Green.** `MutantVerdict` spec pinning the flaky-retry decision for a
   single-entry `failed_tests`.
6. Smoke: `rake smoke:integration:all` statuses unchanged; `rake oracle`
   reports 0 new false kills/survivors.

## Acceptance

- Verdict distribution of a full dogfood run is unchanged (fail-fast changes
  wall-clock, never verdicts).
- Wall-clock for the dogfood run drops measurably; record before/after in
  the PR.
- Oracle and smoke suites green.
