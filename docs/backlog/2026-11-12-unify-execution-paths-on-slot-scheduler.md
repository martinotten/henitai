# Unify Mutant Execution on the Slot Scheduler

Status: proposed — **prioritized** (next after resumable runs, before the
Rails matrix R3 of `2026-11-12-ruby-rails-version-support-matrix.md`)
Date: 2026-11-12
Severity: High (two drivers duplicate timeouts, retries and cleanup; every
new execution feature is built twice; doubles the Rails compatibility matrix)
Source: requirement intake 2026-11-12 while sizing the Ruby/Rails matrix
(`2026-11-12-ruby-rails-version-support-matrix.md`): `jobs: 1` vs.
`jobs > 1` and `fork_server` off/on are four separately testable paths.

## Summary

Mutants are executed by two drivers today: a synchronous one for
`jobs: 1` and the event-loop `SlotScheduler` for `jobs > 1`. Each has its
own fork-server variant. Make `SlotScheduler` the only driver for mutant
runs; `jobs: 1` becomes a scheduler with one slot. `jobs` is then a pure
concurrency number, and `fork_server` remains the only mode switch.

## Current state

What is shared already: the child itself. Both drivers fork through
`Integration#spawn_mutant` (`RspecProcessRunner#spawn_mutant`), so
activation, test loading and child reporting are identical.

What differs is everything around the child — waiting, timeouts,
process-group cleanup, flaky retries, progress, signal handling:

| Concern | `jobs: 1` (synchronous) | `jobs > 1` (scheduler) |
|---|---|---|
| Driver | `ExecutionEngine#run_linear` / `#process_mutant` | `ProcessWorkerRunner` + `SlotScheduler` (+ `slot_scheduler/*`) |
| Wait / timeout | `Integration::Base#wait_with_timeout`, `handle_timeout`, `cleanup_process_group` via `RspecProcessRunner#run_mutant` | `SlotScheduler` deadlines, `ProcessControl`, `Draining` |
| Flaky retries | `FlakyMutantRetrier` | `SlotScheduler::RetryPolicy` |
| INT/TERM | no traps in the linear path | `ProcessWorkerRunner#install_signal_traps` |
| Fork server | `MutantRunner#run_mutant` → `run_through_server`, `wait_for`, `fallback` | `MutantRunner#spawn_mutant` → `spawn_through_server` + `ForkServer::Runtime` |
| Also used by | `ControlRun` (always synchronous, per-mutant boot) | — |

Notes:

- `parallel_execution?` also falls back to the linear driver when
  `jobs > 1` but only one mutant is pending, so even `jobs > 1` users hit
  the synchronous path.
- The synchronous wait code in `Integration::Base` stays needed for the
  baseline suite and coverage bootstrap (`run_suite`); only its use for
  mutant runs goes away.
- The only difference that is genuinely required between fork server on
  and off is *where the child comes from* (local fork after per-mutant boot
  vs. fork from the booted server) and *how its exit is observed*
  (`waitpid` vs. relayed exit event). `ForkServer::Runtime` already
  abstracts exactly this behind the scheduler's runtime interface.

## Proposal

1. Route `jobs: 1` through `ProcessWorkerRunner` with `worker_count: 1`;
   drop `parallel_execution?`'s single-mutant fallback.
2. Move `ControlRun` onto the same driver (a one-slot scheduler run over the
   control mutants) or keep it as the single, documented synchronous user.
3. Remove `ExecutionEngine#run_linear`/`#process_mutant`,
   `FlakyMutantRetrier`, `RspecProcessRunner#run_mutant`,
   `Integration#run_mutant` for mutants, and
   `ForkServer::MutantRunner#run_mutant`/`run_through_server`/`wait_for`/
   `fallback` once no caller remains.
4. Rough size: about 150 lines of production code plus their specs go
   away; more importantly one execution semantics remains (timeouts,
   retries, process-group cleanup, signal handling, checkpointing).

## Which modes to offer

- **`jobs`:** keep, as a number only. One slot vs. many is a resource
  decision, not a behavioural mode.
- **Per-mutant boot:** cannot go away. It is the fallback when the fork
  server dies or cannot boot, the path for integrations without fork-server
  support, and the path for control runs. It is also the semantically safer
  choice for suites whose boot opens connections or threads.
- **Fork server:** keep. Paying the boot once is the main speed lever for
  Rails-sized suites (ADR-15). It is opt-in until the Rails matrix shows it
  is safe; the long-term direction is default on, with off as the escape
  hatch.
- Consequence: two user-visible modes (`fork_server` off/on), each with any
  `jobs`. The compatibility matrix tests both with `jobs: 2`; `jobs: 1` is
  covered by unit specs as the one-slot case.

## Risks / to check in planning

- Progress output and log behaviour for `jobs: 1` must stay as today
  (terminal reporter tests, smoke suites).
- Overhead of the event loop for one slot (`ProcessWakeup`, select) should
  be negligible; measure on the dogfood run.
- Resumable runs (ADR-16, `feat/resumable-runs`) checkpoint and handle
  `SignalException`; land or rebase that work first so both changes do not
  collide in `ExecutionEngine`.
- Oracle (`rake oracle`) and `rake oracle:reuse` must be unchanged.
- Measure MS/MSI of `ExecutionEngine`, `ProcessWorkerRunner`,
  `SlotScheduler` and `ForkServer::MutantRunner` before and after; the sum
  must not fall (AGENTS.md extraction rule applies analogously).

## Acceptance criteria

- `jobs: 1` and `jobs: N` run mutants through the same driver; the
  synchronous mutant path and `FlakyMutantRetrier` are gone.
- INT/TERM, timeouts and flaky retries behave identically for any `jobs`.
- Smoke suites and oracle results unchanged; dogfood wall time for
  `jobs: 1` not measurably worse.
- Architecture document and ADR-15 describe one driver and two modes; a
  new ADR records the unification with an Execution paths section
  (`docs/architecture/adr/README.md` maintenance rule).
- One shared contract spec covers the driver for `jobs: 1` and `jobs: N`,
  with and without fork server.

## Background

Origin: parallel execution was added as a second driver next to the linear
one (`1af9f05 Add parallel execution`); flaky retries and the fork server
(#48) were then implemented once per driver. See `MISTAKES.md`
(2026-11-12) and "No Parallel Implementations" in `AGENTS.md` for the
rules that should stop this from recurring.

## Related

- `docs/architecture/adr/ADR-15-fork-server-execution-model.md`
- `docs/architecture/adr/ADR-16-resumable-runs-via-history-checkpoints.md`
- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md`
