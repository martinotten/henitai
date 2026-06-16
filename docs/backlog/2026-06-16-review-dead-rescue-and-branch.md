# Tighten Broad Rescues and Remove Dead Defensive Branch

Status: backlog
Date: 2026-06-16
Severity: Low
Source: 2026-06-16 structured review

## Summary

A few spots swallow all `StandardError` and hide real failures, and one
defensive branch in the process-worker scheduler is unreachable dead code. These
are small robustness/clarity fixes.

## Problem

- `lib/henitai/per_test_coverage_collector.rb:55-57`: `current_snapshot` rescues
  all `StandardError` and returns `nil`, masking `Coverage` not-started errors,
  encoding errors, and genuine bugs. Caller then silently produces an empty
  per-test coverage map — hard to debug.
- `lib/henitai/unparse_helper.rb` `safe_unparse`: broad `rescue StandardError`
  falls back to a type-name string, so reports show operator names instead of
  source and hide unparser bugs.
- `lib/henitai/process_worker_runner.rb:343-352` `remaining_slot_timeout`: the
  `if slot.draining` branch reads `slot.term_sent_at_monotonic`
  (`nil`-initialized). It is effectively dead: `process_cycle` calls
  `drain_draining_slots` (line 98) — which synchronously removes all draining
  slots (line 274) — before `wait_for_next_event`/`next_event_timeout`
  (line 102). So `next_event_timeout` never observes a draining slot. (Reviewed
  and confirmed NOT a live nil-deref crash, contrary to an initial flag.)

## Fix Plan

1. **Narrow the coverage rescue.** In `current_snapshot`, rescue only the
   specific expected error (e.g. the `Coverage`-not-running case) and let other
   `StandardError`s propagate. If a `nil` fallback is genuinely needed, log a
   warning so the failure is visible.
2. **Narrow `safe_unparse`.** Catch the specific unparser/encoding error class
   it is meant to tolerate; let unexpected errors surface (or at minimum warn).
   A silent operator-name fallback should be the documented last resort, not a
   catch-all.
3. **Resolve the dead branch.** Either delete the `if slot.draining` branch in
   `remaining_slot_timeout` (since it is unreachable), OR — if the team wants
   defensive safety against future refactors — guard the `nil` explicitly and
   add a comment explaining the invariant (drain removes draining slots before
   the wait). Add a spec documenting the invariant either way.
4. Run full suite; confirm no behavior change.

## Acceptance

- No catch-all `rescue StandardError` that silently returns `nil`/fallback
  without logging in the two named spots.
- The draining branch is either removed or explicitly guarded + documented +
  spec'd.

## Related

- [[2026-06-16-review-flaky-count-parallel]]
