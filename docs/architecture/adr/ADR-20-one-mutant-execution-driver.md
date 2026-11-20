# ADR-20: One Mutant Execution Driver

Status: accepted (2026-11-20)

## Context

Mutants were executed by two drivers. `jobs: 1` (and `jobs > 1` with a
single pending mutant) ran synchronously: `ExecutionEngine#run_linear`
called `Integration#run_mutant`, which forked, waited with
`Integration::Base#wait_with_timeout` and cleaned up the process group;
`FlakyMutantRetrier` retried flaky kills; a `ControlGate` ran controls
inline through `ControlRun#run_for`; the fork server had its own synchronous
`MutantRunner#run_mutant`/`wait_for`/`fallback`. Every other `jobs` value ran
through `ProcessWorkerRunner` and `SlotScheduler`, which own spawning,
reaping, timeouts, draining, flaky retries, control jobs and INT/TERM/HUP
handling.

Every execution feature since parallel execution (flaky retries, the fork
server, control runs, resumable runs) was built once per driver. The two
copies diverged: only the scheduler trapped signals or marked kills whose
retry a shutdown cut short. See
`docs/backlog/2026-11-12-unify-execution-paths-on-slot-scheduler.md` and
"No Parallel Implementations" in `AGENTS.md`.

## Decision

`SlotScheduler`, driven by `ProcessWorkerRunner`, is the only driver for
mutant and control processes. `jobs` is a concurrency number: `jobs: 1` is a
scheduler with one slot, and `jobs: 0` or `nil` mean one slot too.

- `ExecutionEngine` always hands the pending mutants to one
  `ProcessWorkerRunner`. The single-mutant fallback to the synchronous path
  is gone.
- Control runs are always scheduler jobs (`SlotScheduler::ControlSlots`).
  `ControlGate` needs a launcher; there is no inline control.
- Removed: `ExecutionEngine#run_linear`/`#process_mutant`,
  `FlakyMutantRetrier`, `ControlRun#run_for`, `Integration#run_mutant`
  (`Base`, `MutantRunSupport`, `Minitest`, `RspecProcessRunner`) and
  `ForkServer::MutantRunner#run_mutant` with its synchronous wait and
  fallback.
- The synchronous wait in `Integration::Base` stays for the processes that
  are not mutants: the baseline suite and the coverage bootstrap
  (`run_suite`).
- Children of `jobs: 1` see `HENITAI_WORKER_SLOT=0`, as before.

## Execution paths

- Paths removed: the synchronous mutant driver with its fork-server variant,
  its retry loop and its inline control runs.
- Paths kept: one driver. Its only mode switch is `mutation.fork_server`,
  which changes where a child comes from (local fork after per-mutant boot,
  or fork from the booted server) and how its exit is observed (`waitpid`
  or a relayed exit event). `ForkServer::Runtime` and
  `ForkServer::MutantRunner#spawn_mutant` encapsulate exactly that
  difference behind the scheduler's runtime and integration interfaces.
- Test matrix: from four driver combinations (`jobs` 1/N × fork server
  off/on) to two modes. One shared contract spec
  (`spec/henitai/execution_engine_run_process_spec.rb`) runs real mutants
  through all four combinations and requires identical verdicts and no
  leftover child; `spec/henitai/execution_engine_spec.rb` covers the engine
  with one slot and with several on fake children. Smoke suites and the
  Rails matrix can run `jobs: 2` with and without the fork server.

## Consequences

- INT/TERM/HUP, timeouts, process-group teardown, flaky retries,
  retry-cut-short marking and checkpointing behave identically for every
  `jobs` value. A signal during a `jobs: 1` run now drains through the
  scheduler and raises `Interrupt`, which the runner turns into saved
  progress (ADR-19).
- A `jobs: 1` run pays the event loop (`ProcessWakeup`, `IO.select`) per
  mutant. The cost is a select per child exit, negligible next to a fork
  and a test run.
- About 200 lines of production code and their specs go away.

## Related

- ADR-02 (process isolation), ADR-14 (control runs), ADR-15 (fork server),
  ADR-19 (resumable runs)
