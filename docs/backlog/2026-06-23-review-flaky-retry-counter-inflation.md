# Flaky Retry Counter Inflated by Failed Respawns

Status: done
Date: 2026-06-23
Severity: Medium
Source: 2026-06-23 structured review

## Summary

`ProcessWorkerRunner#retry_slot` increments `@flaky_retry_count` *before*
attempting the respawn. If `spawn_mutant` raises, the slot is recorded as a
spawn failure (`compile_error`) and never actually retried — but the flaky
counter was already bumped. The reported flaky count/ratio is overstated and
can wrongly trip the 5% flaky-test warning.

## Problem

- The logic cited above (originally `process_worker_runner.rb:373-387`) moved
  to `lib/henitai/slot_scheduler.rb#retry_slot` during the class-size
  decomposition work; same bug, new location.
- `@flaky_retry_count += 1 if slot.retry_count.zero?` ran before
  `integration.spawn_mutant(...)`, which can raise.
- The `rescue StandardError` deletes the slot and calls `record_spawn_failure`
  — the retry did not happen, yet the counter already counted it.
- Net effect: a mutant whose first retry fails to spawn still adds `1` to the
  flaky statistic. Mirrors the spirit of the earlier
  [[2026-06-16-review-flaky-count-parallel]] fix (flaky stats must be honest).

## Fix Plan

1. **Reproduce (red).** Spec: stub `integration.spawn_mutant` to raise on the
   retry call for one mutant. Run through `ProcessWorkerRunner`. Assert the
   reported flaky retry count is `0` (no successful retry happened). Fails
   today because it reports `1`. — done
   (`spec/henitai/process_worker_runner_spec.rb`, "does not count a retry
   whose respawn fails to spawn").
2. **Move the increment after spawn succeeds.** Reorder so
   `@flaky_retry_count += 1 if slot.retry_count.zero?` runs only once
   `spawn_mutant` returns a handle (before `slot.retry_count += 1`, or guard on
   the post-spawn state). The spawn-failure rescue path must not leave the
   counter incremented. — done (`lib/henitai/slot_scheduler.rb#retry_slot`).
3. **Confirm the success path still counts once.** Existing flaky specs stay
   green; the first successful retry of a given slot still increments exactly
   once (subsequent retries of the same slot do not double-count — preserve the
   `slot.retry_count.zero?` guard semantics). — done, confirmed via existing
   "flaky retry counting" examples staying green unchanged.
4. Green new spec; run full suite. — done (1128 examples, 0 failures;
   rubocop 199 files, 0 offenses).

## Acceptance

- A retry whose respawn fails does not increment the flaky counter. — met.
- A successful first retry increments exactly once per slot. — met.
- New spec covers the failed-respawn path. — met.

## Related

- [[2026-06-16-review-flaky-count-parallel]]
