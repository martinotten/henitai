# Forked Worker Processes Orphan and Leak When the Parent Is Hard-Killed

Status: done (2026-08-21)
Date: 2026-07-09
Severity: Medium
Source: discovered while investigating a long-running run's memory growth
(see `2026-07-09` OOM work: child-output cap + checkpoint reports). A user's
process list showed ~13 orphaned `ruby` workers, each ~600–900 MB and with
16–17 min CPU time, idle, surviving a killed run — ~10 GB never reclaimed.

## Summary

Each mutant runs in a forked child that puts itself in its own process group
(`RspecProcessRunner#spawn_mutant`, `Process.setpgid(0, 0)`). The scheduler
kills a child's whole process group on timeout / graceful shutdown
(`Integration::Base#cleanup_process_group`, SIGTERM → SIGKILL), and the runner
traps `INT`/`TERM`/`HUP` to drain in-flight slots
(`ProcessWorkerRunner#install_signal_traps` → `request_shutdown` →
`SlotScheduler#interrupt_active_slots`). All of that only runs while the parent
event loop is alive.

If the parent is hard-killed (`kill -9`, OOM-killer, crash), it runs no
cleanup. The forked children — in their own process groups — receive no signal,
get reparented to `launchd`/`init`, and keep running (or block) indefinitely.
Because each carries a full loaded Ruby/RSpec image (plus, pre-cap, whatever
heap a runaway mutant grew), the leak is multi-GB.

The tighter auto-calibrated timeout ceiling (`mutation.max_timeout`, added in
the OOM work) shortens how long a *running* orphan survives, but a child
blocked on I/O, or one between test end and reap, can still linger; and nothing
reaps an orphan whose work already finished.

## Impact

- Multiple GB of RAM held by dead-run workers until the user manually hunts and
  `kill -9`s them (they have no obvious link back to the run that spawned them).
- Repeated interrupted runs stack orphans, degrading the whole machine.
- Confusing: `ps` shows dozens of `ruby` procs with no live parent, easily
  mistaken for a still-running or runaway job.

## Fix Sketch

**Recommended — child self-death watchdog (handles `kill -9` too).** A signal
handler cannot catch `SIGKILL`, and orphans cannot be reliably matched back to
a dead parent after reparenting, so the robust fix lives *in the child*: have
each forked worker watch its parent and exit when the parent is gone.

- Capture the parent pid in the child right after fork (before `Process.exit`
  in `RspecProcessRunner#spawn_mutant`).
- Start a lightweight daemon watcher thread in the child that either:
  - polls `Process.ppid` / `Process.kill(0, parent_pid)` every ~1–2 s and calls
    `exit!(2)` once the parent is gone (portable, no native deps), or
  - on macOS/BSD uses a `kqueue` `EVFILT_PROC`/`NOTE_EXIT` watch on the parent
    pid; on Linux `prctl(PR_SET_PDEATHSIG, SIGKILL)` — faster, platform-specific.
- Keep it in the child lifecycle helper (`Integration::MutantRunSupport#run_in_child`
  / `ChildRuntimeControl`) so both the RSpec and Minitest paths inherit it, and
  gate it behind an env flag so tests can disable it.

Start with the portable poll — simplest, cross-platform, and 1–2 s of extra
orphan lifetime is fine given the timeout ceiling already bounds active work.

**Weaker alternatives considered:**

- *PID/session file + startup reaper / `henitai doctor`:* parent writes
  `reports/henitai-run.pid` with its pid + a run token stamped into each child's
  env (`HENITAI_RUN_TOKEN`); a later `henitai run` (or an explicit subcommand)
  finds processes carrying a token whose parent pid is dead and kills them.
  Reaps *finished* orphans too, but is race-prone, only triggers on the next
  invocation, and needs a reliable way to enumerate tagged processes. Useful as
  a complementary cleanup command, not the primary mechanism.
- *Nothing / document only:* rely on the timeout ceiling and tell users to stop
  runs with Ctrl-C / SIGTERM rather than `kill -9`. Insufficient — crashes and
  the OOM-killer also orphan.

## Test Plan

- Unit: spawn a child through the integration's fork path with the watchdog
  enabled, `kill -9` the (test-stand-in) parent, assert the child exits within
  the poll window. Use a short poll interval via the env flag.
- Regression: a normal run (parent alive) is unaffected — watchdog never fires,
  no measurable per-child overhead; existing `slot_scheduler` / process-runner
  specs stay green.
- Smoke: `rake smoke:integration:all` still passes (watchdog thread must not
  interfere with normal child stdout capture or exit status).
- Manual: start a run, `kill -9` the parent pid, confirm `ps` shows no surviving
  `ruby` workers after the poll window.

## Live repro (2026-07-12)

Reproduced in the wild during a dogfood `henitai run --incremental`:

- Ctrl-C killed the foreground parent (pid 4217), but one forked child
  (`henitai run --incremental`, pid 40441) survived, was reparented to
  launchd (ppid 1), and kept executing detached.
- The child inherited the parent's flock fd on `reports/.henitai-run.lock`,
  so every subsequent run failed with `ConcurrentRunError` naming the *dead*
  parent pid from the lock metadata — misleading until
  `lsof reports/.henitai-run.lock` exposed the orphan.
- The orphan ignored SIGTERM and required SIGKILL.

Two consequences for this ticket:

1. The Ctrl-C path (SIGINT to the foreground process group) is not
   sufficient — at least one child survived it, so the watchdog must not
   assume signal delivery ever reached the child.
2. Interim diagnosability shipped separately: `ReportsDirectoryLock`
   now detects a dead recorded owner via `Process.kill(0, pid)` and appends
   an orphaned-child hint (incl. the `lsof` command) to the contention
   message.

## Resolution (2026-08-21)

Implemented as the recommended portable poll, plus the inherited-fd fix the
2026-07-12 live repro exposed. No kqueue or PDEATHSIG; those can be layered
behind the same interface later.

- `Henitai::OrphanWatchdog` polls with a two-armed predicate. A changed
  `Process.ppid` is definitive -- reparenting cannot be faked by pid reuse --
  but stays equal while the parent lingers as a zombie, which a
  `Process.kill(0, parent_pid)` probe catches. Every collaborator is
  injectable, so the decision logic is specced with no forks.
- `parent_pid` is captured in the *parent*, before `Process.fork`. Reading
  `Process.ppid` in the child would race the very death being detected: a
  parent dying between fork and that read leaves the child with ppid 1 as its
  baseline, so it would never consider itself orphaned.
- Exit code is 2, because `ScenarioExecutionResult.status_for` maps that to
  `:compile_error` while codes from 3 up map to `:killed`. A false positive is
  therefore visible in the report rather than silently inflating the mutation
  score.
- `Henitai::ProcessLiveness` extracts the pid probe that
  `ReportsDirectoryLock#dead_owner?` had inlined, so the EPERM-means-alive
  rule lives in one place. `reports_directory_lock_process_spec.rb` passes
  unedited, which was the acceptance signal for that extraction.
- `Integration::ChildBootstrap.after_fork!` names the sequence -- close
  inherited handles, `setpgid`, start watchdog -- and lives under
  `Integration`, so the RSpec and Minitest paths both get it via the shared
  `MutantRunSupport#spawn_mutant`. The hook went at the fork site rather than
  in `run_in_child` as this ticket suggested, because `run_in_child` is
  stubbed with verifying doubles in the process specs and a `parent_pid:`
  kwarg would have forced signature churn on both framework paths for what is
  fork hygiene rather than test execution.
- `HENITAI_CHILD_WATCHDOG=0` disables it; `HENITAI_CHILD_WATCHDOG_INTERVAL`
  sets the poll seconds. The flag is opt-*out*, deliberately inverted relative
  to `HENITAI_DEBUG_CHILD`'s opt-in.

### Inherited flock handle (from the live repro)

`Henitai::InheritedFdRegistry` lets the child close handles it inherited.
`ReportsDirectoryLock` registers its handle for the duration of the lock, and
the child closes its copy first thing after forking. `close_all!`
deliberately does *not* take the registry mutex: `fork` can land while
another thread holds it, only the forking thread survives into the child, and
waiting on a mutex whose owner does not exist would hang the child forever.

### Verification

Both halves were falsified before being accepted, in
`spec/henitai/orphan_watchdog_process_spec.rb`:

- with `HENITAI_CHILD_WATCHDOG=0`, the orphan-death example fails (the child
  survives its killed parent);
- with the `close_all!` call removed, the lock-release example fails with
  `ConcurrentRunError`.

Manual A/B on a real `bundle exec henitai run --jobs 2`, SIGKILLing the
parent mid-run: with the watchdog enabled no child survived; with it disabled
the mutant child reparented to ppid 1 and was still running 12 seconds later.
`rake smoke:integration:all` produced an unchanged status tally (8 killed, 4
survived, 11 ignored on both frameworks) and no `CompileError`, i.e. no false
positives from the watchdog in real forked children.

### Incidental finding worth keeping

Specs that execute the fork block in-process (`stub_process_fork` in
`spec/henitai/integration/rspec_spec.rb`, 21 call sites) run the child
bootstrap in the test process. Given the test process as its `parent_pid`,
the watchdog sees `ppid != parent_pid`, concludes it is orphaned, and calls
`exit!(2)` -- killing the RSpec run with no failure output and no summary.
Those hooks now stub `OrphanWatchdog.start` alongside the `Process.setpgid`
stub they already had. Only `bin/verify-process-free-specs` caught this; the
plain suite did not.
