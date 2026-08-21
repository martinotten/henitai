# Extract `SlotScheduler::DrainCycle` and Friends

Status: backlog
Date: 2026-08-21
Severity: Medium (spec coupling and class size, not user-visible behavior)
Source: deliberately deferred second wave of the `send`-reach paydown; see
[`2026-08-21-review-send-slot-scheduler-draining-spec.md`](2026-08-21-review-send-slot-scheduler-draining-spec.md)

## Summary

After `SlotTable` and the four policy objects (`RetryPolicy`, `SlotDeadline`,
`TestFileSelection`, `DrainVerdict`) land, the residual `send` reach in
`slot_scheduler_spec.rb` and `slot_scheduler/draining_spec.rb` is confined to
drain and dispatch mechanics: `dispatch_slot_result`(9),
`reap_and_finalize_slot`(6), `retry_slot`(3), `complete_slot`(3),
`prune_raced_draining_slots`(2), `wait_for_drain_window`(2),
`signal_draining_slots`(1), `broadcast_term`(1), `reset_slot_for_retry`(1).

## Problem

These are the orchestration steps of the drain state machine rather than
policies with a clean input/output shape, so they resist the extraction pattern
that works for the rest of the file. Pulling them apart is a larger design task:
it touches the two-phase `SIGTERM` → window → `SIGKILL` sequence, the blocking
final reap, and the retry path — the parts most likely to produce flake or
leaked processes if got wrong.

## Fix Sketch

Three collaborators, each with its own spec:

- `SlotScheduler::DrainCycle` — takes slot table, runtime, wakeup, integration,
  progress reporter, results sink and the verdict builder. Public `#run`,
  `#prune_raced`, `#broadcast_term`, `#wait_for_window`, `#kill_all`,
  `#finalize`.
- `SlotScheduler::SlotSpawner` — the fork-into-slot path.
- `SlotScheduler::ResultDispatcher` — `dispatch_slot_result` plus the retry
  decision, consuming `RetryPolicy`.

## Why This Is Deferred, Not Dropped

The residual counts are frozen as budgets in
`spec/infra/private_method_reach_spec.rb`, each with a reason string pointing
here. That makes the deferral safe in both directions: the residue cannot grow
(the budget is a ceiling), and it cannot be quietly left behind either — the
ratchet's "requires a budget to be tightened once a spec beats it" example fails
the moment this work lands without the budgets coming down with it.

## Test Plan

- Capture `bundle exec henitai run 'Henitai::SlotScheduler#*'` MS/MSI before
  starting; the sum across host and new collaborators must not fall below it.
- New fork-using specs must be named `*_process_spec.rb`
  (`bin/verify-process-free-specs`, `spec/infra/process_spec_policy_spec.rb`).
- `bundle exec rake smoke:integration:all` is the real gate for the drain path —
  unit specs use a fake `Runtime` and never exercise real signals.
- Watch `Metrics/ClassLength` (200): this extraction should take
  `SlotScheduler` well under it.
