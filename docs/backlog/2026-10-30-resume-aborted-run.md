# Resume an Aborted Run with `--incremental`

Status: backlog (design: [ADR-16](../architecture/adr/ADR-16-resumable-runs-via-history-checkpoints.md), proposed)
Date: 2026-10-30
Severity: High (an aborted multi-hour run is lost completely)
Source: user report against 0.6.0 — "Henitai cannot resume an aborted run.
`--incremental` would repeat almost everything, because previous results are
stored for reuse only at the end of a complete run, and this run was aborted."

## Summary

Verdicts reach the SQLite history — the only source `--incremental` reads
(ADR-11) — once, at the end of a run. Mid-run checkpoints exist only for the
JSON/HTML report; they carry no fingerprints and contain detections that the
end-of-run `ControlRun` (ADR-14) has not verified. ADR-16 runs each group's
control at its first detection, so every emitted verdict is final, binds
fingerprints to the inputs that were executed, and then checkpoints final
verdicts into the history store.

## Current Behavior (0.6.0, `dd582fb`)

- `Runner#build_result` → `persist_history` → `MutantHistoryStore#record`,
  after `ExecutionEngine#execute` has run all mutants and `verify_controls`.
- `ExecutionEngine#verify_controls` passes only the initially pending mutants
  to `ControlRun`, which also skips `from_cache?` mutants.
- `CheckpointReporter#progress` flushes the canonical JSON report every
  `checkpoint_every` (200) mutants or `checkpoint_interval` (30 s); it has no
  flush on interrupt and serialises unverified detections.
- `ProcessWorkerRunner` traps INT/TERM/HUP only around its event loop, drains
  the slots and raises `Interrupt`. Linear mode installs no traps. Nothing in
  `Runner` or the CLI rescues the signal.
- `SlotScheduler::RetryPolicy` vetoes flaky-kill retries during shutdown.
- sqlite3 2.9.6 `Database#transaction` rolls back only on `StandardError`;
  an `Interrupt` inside the block commits.
- `RunnerDependencies#progress_reporter` builds a new reporter per call.

## Workaround for 0.6.0 Users

Split the run by subject patterns (`henitai run 'Foo::*'`, `'Bar::*'`, …).
Each completed scoped run records its verdicts; a final
`henitai run --incremental` reuses them. Derived from the code
(`persist_history` runs for scoped runs too), not yet verified end to end.

## Implementation Plan (TDD, one commit per step)

Each step: failing spec first, smallest change, refactor, then RuboCop,
`steep check` (RBS in `sig/henitai.rbs` for touched Steep entry points), the
relevant specs and the full suite. New specs stay within the private-method
reach ratchet: extract public collaborators instead of reaching in.

The order keeps every intermediate commit safe. Nothing writes mid-run
verdicts to the history store until every verdict is final (steps 2–4) and
every fingerprint is bound to the inputs that were executed (step 5).

1. **`control_runs` in `ReuseContext`.** Spec: toggling it changes the
   fingerprint; a verdict recorded under the other setting is not reused.
2. **`ControlRun#verify_group` + `ControlGate` (linear).** Extract per-group
   control execution. The gate owns held mutant/result pairs, runs the
   group's control once, memoizes the outcome, reclassifies mutant *and*
   result, delivers each pair exactly once and releases output afterwards.
   Wire it into the linear path and drop the end-of-run pass there. Specs:
   hold/release, failing control reclassifies held and later detections,
   consistent mutant/result status, `control_runs: false` passes through,
   survivors and no-coverage are never held. `rake oracle` must show no new
   false kills.
3. **ControlGate in the parallel path.** Implement the control job contract
   from ADR-16 §2 as a collaborator of `SlotScheduler`, which is already near
   its class-length limit: front of queue, recorded test files, no flaky
   retries, no mutant progress, local child registered with the fork-server
   runtime (shared local-spawn adapter with `ForkServer::MutantRunner`'s
   fallback, boot-inclusive timeout) instead of a server fork, every
   terminal outcome (pass, fail, timeout incl. draining, spawn failure,
   shutdown) reported to the gate once, slot freed while the gate waits, run
   completion includes pending controls. Hand result ownership to the gate
   instead of releasing output in `finalize_slot`. Remove `verify_controls`.
   Specs per outcome, plus a run whose last outstanding work is a passing
   control — with the fork server on, it must complete normally, not time
   out.
4. **Shutdown-shortened kills.** A kill finalized under the shutdown retry
   veto carries a marker and gets no execution fingerprints (step 5). Spec on
   `RetryPolicy`/finalization.
5. **`ExecutionProvenance`.** Snapshot before Gate 1 (content hash, size and
   `mtime` of every source and test file, fresh `ReuseContext` fingerprint).
   Recheck after Gate 3, after fork-server boot, at dispatch and before each
   write; drift is sticky per file. Snapshot the test dependency files and
   their membership too; any dependency drift invalidates the rest of the run. Recompute the `ReuseContext` fingerprint
   before *every* write (checkpoint and end-of-run `record`). Attach execution
   fingerprints only to mutants without drift. `VerdictCache` stores those for
   both writers and stops recomputing. Specs: edit between parsing and
   snapshot recheck; edit during fork-server boot that is restored before
   dispatch; edit of a test between execution and persist; dependency edit
   with checkpointing disabled, after the last checkpoint, and after a failed
   checkpoint; a helper (`spec_helper.rb`) edited during fork-server boot and
   restored to its original content before dispatch, leaving a changed
   `mtime` — all yield no fingerprints from either writer. Unchanged inputs yield
   fingerprints equal to today's for the same content. This step already
   hardens the end-of-run write of 0.6.0.
6. **Store: `runId`, `checkpoint`, safe transactions.** `status_history`
   entries carry `runId`, same-run upsert replaces; `#checkpoint` upserts
   without a run row; writes run in a signal-deferral section (temporary
   INT/TERM/HUP traps that record the signal, restore the handlers and
   re-send it afterwards — `Thread.handle_interrupt` does not defer
   signal-raised `Interrupt`) and roll back explicitly on any exception.
   Specs: checkpoint + record → one entry, one run row; an exception raised
   inside an upsert leaves the database unchanged; a signal sent during a
   write is delivered after commit with handlers restored.
7. **`HistoryCheckpointer` + `flush` + interrupt handling.** Observer with an
   injected clock like `CheckpointReporter`; `flush` on both checkpointers and
   the composite; wired in `CompositeProgressReporter.for` (not for dry runs
   or the recipe fast path). A failing write is contained: warn once, keep the
   batch for the final `record`, stop checkpointing. `Runner` keeps the
   reporter, rescues `SignalException` around Gate 4 inside the lock, flushes
   each observer in its own rescue, reports committed verdicts, re-raises the
   original exception. Specs with a fake engine raising `Interrupt` and
   `SignalException.new("TERM")`; a failing flush does not mask the signal;
   a failing checkpoint does not unwind the engine. CLI exit-code specs
   unchanged.
8. **End to end.** Extend `rake oracle:reuse` (or a smoke task) with real
   signals on the RSpec fixture: INT, TERM and HUP; linear and `jobs: 2`;
   fork server on and off; including a signal while a control is in flight.
   Assert: restored handlers, a consistent database, no remaining child
   processes, reuse > 0 on `--incremental`, and verdicts equal to a fresh
   uninterrupted run. Also an all-cached resume and a resume after a test
   file edit.
9. **Docs.** README (resuming an aborted run), `architecture.md` (Gate 4/5,
   control timing, input snapshot), `AGENTS.md` execution-model bullets on
   ADR-14 timing and persistence, ADR-16 → accepted, ADR index, CHANGELOG.

## Acceptance Criteria

- After a run interrupted by INT, TERM or HUP — linear and `jobs > 1`, fork
  server on and off — a `henitai run --incremental` reuses every Killed or
  Survived generated mutant that was emitted and committed before the
  interrupt, unless ADR-11 rejects it anyway (ambiguous stable id, changed
  source or tests, changed `ReuseContext`, missing per-test map for
  survivors), its inputs drifted during the run, or it is a
  shutdown-shortened kill. Timeouts, errors and held detections re-execute.
- After a SIGKILL of the parent, at most the last unflushed batch is lost.
- For generated mutants with controls enabled, no persisted or reported
  Killed verdict skipped its group's control; `rake oracle` shows no new
  false kills.
- No persisted fingerprint describes content other than what the verdict was
  produced with, except for the residual risk ADR-16 §4 accepts (a file
  rewritten with its `mtime` restored).
- A resumed run's verdicts equal those of a fresh run (`rake oracle:reuse`).
- One `status_history` entry per mutant per run; no `runs` row for aborted
  runs.
- Existing history databases keep working without manual migration; exit
  codes are unchanged.
- The mutation score of the touched classes does not fall (dogfood before
  and after).

## Open Questions

- Should a resumed run's report say so (e.g. `resumedFrom` in the vendored
  schema extension), or is `fromCache` per mutant enough?
- Should the interrupt message print the exact resume command, including the
  original subject patterns and `--since`?
