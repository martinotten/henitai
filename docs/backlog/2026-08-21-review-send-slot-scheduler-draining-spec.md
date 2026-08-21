# `slot_scheduler/draining_spec` Uses `send` to Reach Private Drain Helpers

Status: backlog
Date: 2026-08-21
Severity: Medium
Source: discovered while seeding budgets for
`spec/infra/private_method_reach_spec.rb` — this file carries the second-largest
`send` count in the suite (49) and had no ticket

## Summary

[`spec/henitai/slot_scheduler/draining_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/slot_scheduler/draining_spec.rb)
reaches 49 private members of `SlotScheduler` and `SlotScheduler::Draining`:
`integration`(15), `runtime`(7), `slots`(6), `reap_and_finalize_slot`(6),
`build_drain_result`(5), `wait_for_drain_window`(2),
`prune_raced_draining_slots`(2), `pid_to_slot`(2), `signal_draining_slots`,
`record_drain_result`, `draining_slots`, `broadcast_term`.

## Problem

- `lib/henitai/slot_scheduler.rb:93-101` places `private` before
  `attr_reader :pending, :slots, :pid_to_slot, :integration, :config` and the
  `runtime`/`wakeup`/`shutdown?`/`worker_count` delegators. The public face is
  only `enqueue`/`fill_idle_slots`/`done?`/`reap_all_completed_children`/
  `next_event_timeout`, so there is no public read of slot state at all.
- This file was **created** by `99aa8bc` ("test: pay down mutation-coverage debt
  in ChildDebugSupport and SlotScheduler") with the `send` calls already in it.
  The debt did not shrink under the twelve open tickets — it moved into files
  nobody was tracking. That is the case for the ratchet, not just for this fix.
- The highest-value policy in the file — "a real exit status only wins if
  observed before SIGTERM" — is currently 100% `send`-tested.

## Fix Sketch

Extract public collaborators, per
[`2026-07-08-review-send-integration-minitest-spec.md`](2026-07-08-review-send-integration-minitest-spec.md).
A pure public-API rewrite loses mutation coverage, which this repo scores
against itself.

- `SlotScheduler::SlotTable` — owns `@slots`, `@pid_to_slot`, `@next_slot_id`.
  Pays down the same state pokes in `slot_scheduler_spec.rb` (75 sends), so one
  extraction serves both files.
- `SlotScheduler::DrainVerdict` — public `#build(slot, final_status)`, retiring
  `build_drain_result` and `record_drain_result`.
- Drain mechanics proper (`reap_and_finalize_slot`, `prune_raced_draining_slots`,
  `wait_for_drain_window`, `signal_draining_slots`, `broadcast_term`) want a
  `DrainCycle` collaborator; see
  [`2026-08-21-slot-scheduler-drain-cycle-extraction.md`](2026-08-21-slot-scheduler-drain-cycle-extraction.md).

Do **not** satisfy the ratchet with a public `attr_reader :slot_table` that
mechanically renames `send(:slots)` to `slot_table` — that is laundering, not
decoupling. Most `send(:slots)` assertions do not need the table: convert them
to the already-public `done?` / `results` / `flaky_retry_count` first. Reserve
constructor injection for `inject_slot` (lines 38-39), which genuinely must seed
mid-drain state.

`send(:integration)`, `(:runtime)` and friends return objects the spec itself
constructed — hoist those to `let`s with no lib change at all.

## Test Plan

- Capture `bundle exec henitai run 'Henitai::SlotScheduler#*'` MS/MSI before
  starting; the sum across host and new collaborators must not fall below it.
- New collaborator specs assert public interfaces only.
- Lower this file's budget in `spec/infra/private_method_reach_spec.rb` in the
  same commit as each reduction — the ratchet fails otherwise, by design.
