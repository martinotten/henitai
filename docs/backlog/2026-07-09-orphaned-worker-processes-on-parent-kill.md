# Forked Worker Processes Orphan and Leak When the Parent Is Hard-Killed

Status: backlog
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
