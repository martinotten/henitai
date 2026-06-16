# Flaky Retry Count Is Always Zero in Parallel Mode

Status: backlog
Date: 2026-06-16
Severity: Medium
Source: 2026-06-16 structured review

## Summary

`ExecutionEngine#run_parallel` never increments `@flaky_retry_count`, so the
flaky-mutant statistic reported to the user is always `0` whenever the parallel
runner is used — which is the common path.

## Problem

- `lib/henitai/execution_engine.rb:12` initializes `@flaky_retry_count = 0`.
- Only the linear path increments it:
  `lib/henitai/execution_engine.rb:118`
  `mutex.synchronize { @flaky_retry_count += 1 } if retries.positive?`.
- `run_parallel` (line 49) takes no mutex and delegates retry handling to
  `ProcessWorkerRunner` (`should_retry?`, `retry_slot`), which never touches
  `@flaky_retry_count`.
- Result: the reported `flaky:` count and `flaky_ratio` (lines 132, 137) are
  silently `0` in parallel runs. Users get wrong flakiness signal.

## Fix Plan

1. **Reproduce.** Add a spec running a deliberately flaky mutant scenario
   through the parallel path and assert the reported flaky count > 0. It should
   fail today (red).
2. **Decide the source of truth.** `ProcessWorkerRunner` already owns retries in
   the parallel path. Have it count retries (e.g. accumulate `retry_count`
   across slots, or expose a `flaky_retry_count` reader) and return that to the
   engine alongside results.
3. **Thread the count back.** `run_parallel` reads the runner's retry total and
   sets `@flaky_retry_count` before the engine computes `flaky_ratio`. Avoid a
   second incrementing path — single owner per mode.
4. **Alternative (if scope-limited):** if accurate parallel flaky counting is
   out of scope now, make the stat honest — omit or label it "linear-only" in
   the report rather than print a misleading `0`. Prefer the real fix.
5. Green the new spec; run full suite.

## Acceptance

- Flaky count/ratio reflect actual retries in both linear and parallel modes.
- New spec covers the parallel path.

## Related

- [[2026-06-16-review-dead-rescue-and-branch]]
