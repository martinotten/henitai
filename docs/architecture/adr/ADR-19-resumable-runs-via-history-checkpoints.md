# ADR-19: Resumable Runs Through History Checkpoints

Status: proposed

## Context

A full run on a large project can take hours. When it is aborted — Ctrl-C, a
CI job timeout, a closed laptop — every verdict it produced is lost for
reuse:

- `MutantHistoryStore#record` is called once, from `Runner#build_result`,
  after the last mutant and after `ExecutionEngine#verify_controls`. An
  aborted run never reaches it.
- `CheckpointReporter` flushes partial results during the run, but only into
  `mutation-report.json` / `.html`. Those entries carry no fingerprints, so
  `IncrementalFilter` cannot validate them (ADR-11). They also contain
  detections that `ControlRun` has not verified yet (ADR-14).
- A follow-up `henitai run --incremental` therefore re-executes almost
  everything. A user of 0.6.0 reported exactly this.

Constraints:

- **ADR-11** — reuse is decided per mutant by content fingerprints plus the
  run-level `ReuseContext`, stored in the SQLite history. Any doubt resolves
  to re-execution.
- **ADR-14** — a detected verdict counts only when the mutation caused it.
  Today `ControlRun` verifies this in one pass *after* all mutants, per
  `[subject, covering test files]` group, and reclassifies a failed group's
  detections as `CompileError`. A detection observed mid-run is therefore not
  final, and nothing that persists it mid-run may treat it as final.

A first draft of this ADR persisted mid-run kills as "control pending" and
verified them in the resuming run. Review showed that this needs verification
provenance in the store, a reader that rejects pending rows before any writer
exists, control runs for cached mutants that `ExecutionEngine` never hands to
`ControlRun`, and a test set that must be the recorded one rather than a fresh
selection. Each of these is a place where an unverified kill could leak into a
reused verdict. The decision below removes the pending state instead.

## Decision

Make every verdict final before any progress observer sees it, then checkpoint
final verdicts into the history store during the run. Resuming is
`henitai run --incremental`; there is no separate resume command.

1. **Control at first detection (ControlGate).** A `ControlGate` sits between
   the execution engines and the progress observers. When a detected verdict
   (`Killed`, `Timeout`, `RuntimeError`) arrives for a
   `[subject, covering test files]` group that has no control outcome yet, the
   gate holds it and the group's control runs once — same activation path,
   same test files, same integration as today's `ControlRun`. A passing
   control releases the held verdicts unchanged; any other control outcome
   reclassifies them as `CompileError` (ADR-14 reason) and releases them.
   Later detections of a decided group are released or reclassified at once.
   - Linear mode runs the control synchronously.
   - Parallel mode runs the control as a scheduler job (contract below).
   - The end-of-run `ControlRun` pass disappears; `ControlRun` keeps the
     per-group control execution. The number of control runs is unchanged:
     one per group with at least one detection.
   - With `control_runs: false`, the gate passes verdicts through.
   - On interrupt, held verdicts and their unfinished control are dropped;
     they re-execute on resume.
   - **Delivery.** The gate owns each held mutant together with its
     `ScenarioExecutionResult`, including captured output, until it delivers
     them. Each pair is delivered exactly once. A reclassification updates the
     status and reason of both mutant and result, so terminal log decisions
     and `Result` agree. Output is released after delivery, not when the
     scheduler finalizes the slot.

2. **Control job contract (parallel mode).** A control job differs from a
   mutant job:
   - it is enqueued ahead of pending mutants and keeps its group's recorded
     test files — no test reselection;
   - it gets no flaky retries — a control runs once, as today;
   - it counts neither as a mutant result nor as progress;
   - it does not run on the fork server, which does not know it as a
     mutant. It runs as a local child through the same path as the fork
     server's local fallback (`ForkServer::MutantRunner`): the child PID is
     registered with the fork-server runtime so the reap loop sees it, and
     its timeout includes the suite boot. Without a fork server it runs
     through the integration as today;
   - every terminal outcome reaches the gate exactly once — pass, fail,
     timeout (including the draining path), spawn failure, and shutdown,
     which drops the held verdicts;
   - a slot whose mutant is held is freed immediately; only the gate waits.
     The run ends when the queue, the slots and the gate's pending controls
     are all empty.

3. **Control setting is part of the reuse context.** `ReuseContext` gains
   `control_runs`. A verdict recorded with controls disabled is never reused
   by a run with controls enabled, and vice versa. No provenance column is
   needed: within a controls-enabled context, every persisted `Killed` of a
   generated mutant has passed its group's control. Because `ReuseContext`
   includes the henitai version, rows written by 0.6.0 are not reused after
   the upgrade anyway.

4. **Fingerprints bind to the inputs that were executed.** Today
   `VerdictCache` hashes subject sources and covering test files when the
   history is written, so a file edited after execution would be
   fingerprinted with its new content against the old outcome. A shared
   `ExecutionProvenance` object, owned by the run, replaces that.
   - **Snapshot before parsing.** Before Gate 1 the run records size and
     `mtime` (ns) of every source file it may mutate, every test file the
     integration knows, and every test dependency file `ReuseContext` hashes
     (`spec_helper.rb`, `test_helper.rb`, support trees, lockfiles), plus the
     membership of the dependency set.
   - **Check at persistence.** Before a verdict's fingerprints are computed,
     and again right after, its subject file and covering test files must
     match the snapshot. Content hashed while the stat is unchanged is the
     content that was parsed, loaded and executed. Because editors and git
     move `mtime` forward, an edit that is later restored to the same content
     still differs from the snapshot — this covers edits between parsing and
     execution as well as edits during the fork-server boot, without
     intermediate recheck points. A file the snapshot does not know (a test
     created during the run) is never intact.
   - **Execution fingerprints.** A mutant carries execution fingerprints,
     derived from the snapshot, only if neither its subject file nor any of
     its covering test files drifted up to the moment its verdict is
     persisted. Otherwise it carries none and re-executes on the next run.
   - **Every writer checks.** The check runs inside `VerdictCache`, so it
     applies to each checkpoint flush and to the end-of-run `record` alike,
     regardless of whether checkpointing is enabled or has failed. Because the
     dependency files are part of the snapshot, a changed helper or config
     file is caught by the same stat comparison; recomputing the
     `ReuseContext` fingerprint is not needed.
   - **One source for both writers.** `checkpoint` and `record` store exactly
     the mutant's execution fingerprints, or none. Neither recomputes them, so
     the final `record` cannot make a verdict cacheable that a checkpoint
     withheld.
   - **Residual risk.** A tool that rewrites a file and also restores its
     `mtime` during the run is not detected. This is accepted and documented;
     it requires deliberate effort and is outside normal editing or git use.

5. **History checkpoints.** A `HistoryCheckpointer` progress observer is
   composed by `CompositeProgressReporter` next to the terminal reporter and
   `CheckpointReporter`. It uses the same switch and cadence
   (`reports.checkpoint`, `checkpoint_every`, `checkpoint_interval`). Each
   batch goes through a new `MutantHistoryStore#checkpoint`, which upserts
   mutant rows and never writes a `runs` row. The end-of-run `record` writes
   the run row once, as today.
   - A failing checkpoint write is contained in the observer, as the
     end-of-run write already is: it warns once, keeps the batch for the
     end-of-run `record`, and stops checkpointing for the rest of the run.
     It never unwinds the execution loop.
   - The interrupt message reports only verdicts in committed transactions.

6. **One history entry per run.** Each `status_history` entry carries a
   `runId`. An upsert whose `runId` equals the last entry's replaces that
   entry, so checkpoint plus end-of-run record yield one entry per run.
   Legacy entries without `runId` stay as they are.

7. **Interrupt safety.**
   - `Runner` builds the progress reporter once per run and keeps it, so it
     can flush the same observers it handed to the engine.
   - `Runner` rescues `SignalException` (covering `Interrupt`, and `TERM`/`HUP`
     in linear mode, where no trap converts them) around Gate 4 — inside the
     `ReportsDirectoryLock` and after the engine has torn down its children
     and the fork server. It flushes every observer that supports `flush`,
     each in its own rescue so one failure neither blocks the others nor masks
     the signal, prints how many verdicts were saved and that `--incremental`
     resumes, and re-raises the original exception. Exit behaviour stays as in
     0.6.0, including parallel mode turning TERM/HUP into `Interrupt`.
   - Store writes run inside a signal-deferral section: INT/TERM/HUP are
     trapped to a flag for the duration of the transaction, the previous
     handlers are restored, and a recorded signal is re-sent to the process
     afterwards. A signal that arrives during a write therefore lets the
     transaction commit first. `Thread.handle_interrupt` is not enough — a
     probe on Ruby 4.0 showed it does not defer a signal-raised `Interrupt`.
   - Independently, an exception raised inside a write rolls the transaction
     back explicitly: sqlite3 2.x commits a block transaction when a
     non-`StandardError` escapes it.
   - A kill finalized while shutdown vetoed its flaky retry
     (`SlotScheduler::RetryPolicy`) is reported without execution
     fingerprints, so it re-executes on resume.
   - A `SIGKILL` of the parent loses at most the current batch.

8. **Scope.** Checkpointing applies to full, scoped, `--since` and
   `--survivors-from` normal-path runs. It is off for dry runs and for the
   activation-recipe fast path. Recipe stub mutants have no original node, so
   neither today's `ControlRun` nor the gate can control them. The ADR-14
   guarantee below therefore covers generated mutants; recipe stubs keep
   their 0.6.0 behaviour and are never reusable, because they have no source
   range.

## Rejected Alternatives

- **Deferred control ("control pending" rows verified on resume).** The
  first draft of this ADR. It needs verification provenance, a staged
  rollout in which readers learn to reject pending rows before writers exist,
  and control runs for cached mutants against their *recorded* test set. Every
  one of these is a way to leak an unverified kill into the cache.
- **Resume from the JSON checkpoint.** The Stryker schema is the external
  report format (ADR-03) and has no fingerprints. Adding them would duplicate
  ADR-11's store in a weaker place.
- **Checkpoint Survived verdicts only.** Avoids the control question, but
  kills are most of every run; a resume would still re-execute most of it.
- **A dedicated `resume` command or run journal.** A second persistence path
  next to the history store. A resumed run is an incremental run with more
  hits.

## Consequences

- An aborted run costs only the mutants that were not finished, plus held
  detections and at most one batch on `SIGKILL`, provided the follow-up uses
  `--incremental` and the mutants' inputs are unchanged.
- Every verdict any observer sees is final. For generated mutants with
  controls enabled, no persisted or reported Killed verdict skipped its
  group's control. The JSON/HTML checkpoints no longer contain detections
  that a later control would reclassify.
- Editing a source or test file during a run no longer risks a cached verdict
  that does not match its fingerprint; the affected verdicts are simply not
  cached. This also hardens complete runs, not only resumed ones.
- In parallel mode, a detection is reported a little later — after its
  group's control finishes. Total work is unchanged.
- The history store is written several times per run, always by the parent
  process (single-threaded event loop, or under the linear-mode mutex).
- The trend export sees mutant rows from aborted runs but no `runs` row;
  aborted runs are not scored.
- Upgrading invalidates the verdict cache once (new `ReuseContext`
  component, new version), as every release already does.
