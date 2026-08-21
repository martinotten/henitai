# `slot_scheduler_spec` Uses `send` to Reach Private Scheduling Helpers

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/slot_scheduler_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/slot_scheduler_spec.rb)
uses `send` to exercise private slot bookkeeping and timeout helpers.

## Problem

- The tests are strongly coupled to internal scheduler implementation.
- They are more brittle than the public scheduling behavior requires.

## Fix Sketch

- Move the important checks to the public scheduling flow.
- Retain only the smallest private-helper coverage if needed.

## Test Plan

- Replace `send` calls with public scheduling scenarios.
- Verify slot dispatch and timeout behavior through the scheduler API.

## Convention Note (added 2026-08-21)

The Fix Sketch above says to shift coverage to the public entry points. That
prescription is **superseded**: see
[`2026-07-08-review-send-integration-minitest-spec.md`](2026-07-08-review-send-integration-minitest-spec.md),
the one ticket in this family that was actually resolved. It extracted public
collaborators instead, and took `Henitai::Integration::Minitest` from
MS 72.83% / MSI 43.05% to MS 100% / MSI 91.87%.

This repository scores mutation coverage against itself, so a pure public-API
rewrite usually *loses* coverage — the assertions end up further from the logic
they constrain. Extract a public collaborator; rewrite in place only where a
public path genuinely reaches the behavior.

The budget for this file in `spec/infra/private_method_reach_spec.rb` must come
down in the same commit as any reduction here.

## Progress (2026-08-21)

Reach is down from 75 to 57. Two of the three planned waves have landed.

**Wave 1 — the free half.** Every `send(:integration)`, `send(:runtime)` and
`send(:host)` reached back through a private reader for an object the spec had
built itself one line earlier. `build_worker_scheduler` now accepts
`integration:` and `host:`, and `draining_spec`'s builder accepts `runtime:`
and `integration:`.

The `"delegated host readers"` example keeps its four sends deliberately.
`worker_count`/`runtime`/`wakeup`/`shutdown?` are one-line delegators whose only
direct coverage is that example, and this repository scores mutation coverage
against itself — deleting it would lose four killed mutants to buy four points
of budget.

**Wave 2 — the policy objects.** Four extractions, each in
`lib/henitai/slot_scheduler/`:

| Collaborator | Public interface | Retired |
|---|---|---|
| `RetryPolicy` | `#retry?(slot:, result:, shutdown:)` | `should_retry?` ×6 |
| `SlotDeadline` | `#remaining(slot, now)` | `remaining_slot_timeout` ×4 |
| `TestFileSelection` | `#for(mutant)`, `#resolved_empty?(test_files)` | `resolve_test_files` ×3 |
| `DrainVerdict` | `#build(slot, final_status)` | `build_drain_result` ×5 |

`resolved_selection_empty?` moved onto `TestFileSelection` alongside `#for`:
both answer questions about the *same* option keys, and splitting them would
have left the scheduler reading `options[:test_file_resolver]` directly again.

`SlotScheduler` also gained `#finalize_slot` and `#annotate_selection`, split
out of `dispatch_slot_result` and `spawn_into_slot` — the extra collaborator
call pushed both over `Metrics/AbcSize`.

One behavioral note: `RetryPolicy` is memoized lazily rather than built in
`SlotScheduler#initialize`, because the old `should_retry?` short-circuited on
`shutdown?`/`survived?` and so never read `config.max_flaky_retries` for a
killed mutant. `draining_spec` had been relying on that to pass `config: nil`;
it now passes a real config struct, matching what `ProcessWorkerRunner` always
supplies.

### Two mutations in the new code are unkillable by design

Found by falsifying each new spec (breaking the implementation and confirming
the spec goes red). Recording them so they are not mistaken for coverage gaps:

- `SlotDeadline`: `remaining.positive? ? remaining : 0.0` and
  `remaining >= 0 ? remaining : 0.0` are genuinely equivalent — both yield
  `0.0` at the boundary. `EquivalenceDetector` is too conservative to prove it,
  so this will show up as a survivor.
- `TestFileSelection`: `@options.key?(:test_file_resolver)` and
  `@options[:test_file_resolver]` differ only for an explicitly-nil resolver,
  which no caller produces — and under `key?` semantics that input would raise
  rather than fall through. Codifying a crash as expected behavior would be
  worse than leaving the mutant alive.

**Wave 3 — `SlotTable`.** `lib/henitai/slot_scheduler/slot_table.rb` now owns
`@slots`, `@pid_to_slot` and the slot-id sequence. Reach dropped 57 → 21 here
and 22 → 14 in `draining_spec`.

The mechanism matters, because a mechanical rename would have satisfied the
ratchet while leaving the coupling byte-identical: `send(:slots).values.first`
becoming `scheduler.slot_table.values.first` is laundering, and the guard
counts `send`, not coupling. So there is **no public `slot_table` reader on
`SlotScheduler`**. Instead the table is a constructor dependency
(`slot_table:`, defaulting to a fresh one), and each spec builds the table it
asserts against — the same shape already used for `integration:` and
`runtime:`. `draining_spec`'s `inject_slot` seeds the injected table directly.

Table invariants moved out of the host spec entirely into
`spec/henitai/slot_scheduler/slot_table_spec.rb`: slot-id monotonicity and
non-reuse, smallest-free-worker-index with its `|| used.size` fallback branch,
and the pid index's claim-once semantics — `release_pid` answers the slot id the
first time and `nil` the second, which is what stops two threads finalizing one
slot. All eight falsification mutations on the new class are killed.

`SlotScheduler#initialize` picked up a `Metrics/ParameterLists` disable: six
keyword collaborators, all supplied by `ProcessWorkerRunner`. Bundling them into
a context object would only move the list.

**Deferred — drain mechanics.** `dispatch_slot_result` ×9, `retry_slot` ×3,
`complete_slot` ×3, `reset_slot_for_retry` ×1 here, plus the 14 remaining in
`2026-08-21-review-send-slot-scheduler-draining-spec.md`. This is the
`DrainCycle`/`SlotSpawner`/`ResultDispatcher` wave, out of scope for 0.5.0.

Note for whoever picks that up: a slot-fetch cannot be retired while the thing
the slot is fed to is still a private-method `send`. That is why the residue is
what it is, and why the plan's target of "budgets hold `process_guard.rb` and
nothing else" is unreachable without this wave.

### The per-step mutation-score gate could not run

Scoped runs such as `henitai run 'Henitai::SlotScheduler#*'` return zero
mutants: `reports/henitai_per_test.json` is scope-thin, so every mutant in a
fresh scope is classified `NoCoverage` in under a second. That is Part 2 of
`2026-07-08-per-test-coverage-completeness-check.md`, still open. Falsification
of each new spec was used in its place.
