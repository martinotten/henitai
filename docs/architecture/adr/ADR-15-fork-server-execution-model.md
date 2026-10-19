# ADR-15: Fork-Server Execution Model

Status: accepted (opt-in; `mutation.fork_server`, default `false`)

## Context

Every mutant child re-loads the test environment: the spec helper, the test
files and the code they require, and only then activates the mutant (ADR-13)
and runs. Boot dominates wall time (about 27 minutes on the dogfood run). The
2026-10-08 remediation plan (WS4, EXE-13, decision D4) asks for the
environment to be loaded once.

## Decision

With `mutation.fork_server: true`, the parent forks one long-lived *fork
server* after the mutants are generated. The server loads the integration
environment and the union of the run's test files once, activating nothing.
Each mutant then runs in a process forked from the server (ADR-02 isolation
is unchanged: one process per mutant). That process runs the same
`ChildBootstrap.after_fork!`, output capture, coverage suppression, activation,
`FidelityCheck`, `ChildReportStore` and `MutantVerdict` flow as today, so the
ADR-14 guarantees hold.

- Protocol: line-delimited JSON over a `UNIXSocket.pair`. Requests: `run`
  (`request_id`, `mutant_id`, `test_files`, `log_paths`, `env`) and
  `shutdown`. Events: `ready`, `boot_failed` (reason), `spawned`
  (`request_id`, `pid`), `spawn_failed`, `exited` (`pid`, `exitstatus` or
  `termsig`).
- The parent cannot `waitpid` the grandchildren. The server reaps them and
  relays `exited`; the parent builds a duck-typed `ForkServer::Status` that
  `MutantVerdict` accepts. On timeout the parent kills the process group
  directly.
- RSpec: the server runs the example-group load once; each mutant process
  filters `RSpec.world.ordered_example_groups` to the requested files (by
  `metadata[:absolute_file_path]`) and runs them.
- Minitest: the server suppresses `Minitest.autorun` (so the at_exit run can
  neither fire in the server nor double-run in a grandchild), loads the
  environment and the union of test files without running them, and each
  mutant process keeps only the test classes with a test method defined in the
  requested files (suite-level filtering).
- Parallel path (`jobs > 1`): the scheduler runs on `ForkServer::Runtime`,
  which implements the runtime interface it uses. `wait2` completes served
  pids from relayed `exited` events and never calls `waitpid(-1)`, so it cannot
  reap the server. The client socket is added to the select set of
  `ProcessWakeup` (`watch`), so an exit event wakes the event loop. The slot
  env (`HENITAI_WORKER_SLOT`) travels in `run`. Each grandchild leads its own
  process group, so timeouts and INT/TERM teardown signal it directly from
  the parent; the server follows the parent's death through its watchdog.
- If the server dies or stalls mid-run, the client abandons it (kills and
  reaps it) and its outstanding mutants complete with `Status.lost`. A lost
  status is never a verdict: the scheduler runs that mutant again on the
  per-mutant-boot path (no `runtime_error`, no retry count), and later
  mutants take that path too. The mutant processes the dead server left behind
  are killed so a rerun cannot race them.
- Every path that boots the suite in the parent (fallback, lost-server rerun,
  control runs) uses a boot-inclusive timeout (`resolved_timeout(include_boot:
  true)`), handed over through `fallback_timeout:` and `ChildHandle#timeout`;
  the boot-excluded timeout is only right for processes forked from the
  booted server.
- Grandchildren are not our children: `waitpid` raises ECHILD, and one that
  has not yet run `setpgid` has no process group. `ForkServer::GroupKiller`
  therefore signals the group and falls back to the pid itself, and
  `GroupTerminator` (SIGTERM, grace, SIGKILL) probes liveness with
  `kill(0)` instead of waiting. The same fallback serves `Runtime#kill` for
  scheduler timeouts and the server's teardown of live mutants.
  `Integration::Base#cleanup_process_group` is unchanged for direct children.
- The parent socket and the server's wake pipe are registered in
  `InheritedFdRegistry`, so mutant processes close them after the fork.
- If the server cannot boot (`boot_failed`, or it dies), the run falls back to
  per-mutant boot with a one-time warning. A mutant the server cannot spawn is
  run on the old path.
- `TimeoutCalibrator` is built with `include_boot: false` while the server is
  active, because mutant processes no longer pay for boot.

Deviations from the first design sketch: requests and events carry a `type`
key, `run` carries a `request_id` and the server answers with `spawn_failed`
for an unknown mutant id; control runs (which use a mutant not known to the
server) keep the per-mutant boot path, so the calibrator is memoized per
`include_boot` value; the grandchild is forked by the server's own launcher
rather than by `RspecProcessRunner`, so the socket can be closed in it and its
orphan watchdog can watch the server pid.

## Consequences

- Positive: boot cost is paid once per run instead of once per mutant.
- Negative: `before(:suite)` hooks and global monkeypatches of spec files in
  the union run even when a mutant's own test files would not load them;
  connections and threads opened during boot are inherited by every mutant
  process (the same caveat as the Rails preloader).
- Scope: RSpec and Minitest, with any `jobs`. Control runs keep per-mutant
  boot. Minitest filtering is per class, not per method. The oracle
  (MS/false-kill/false-survivor numbers identical in both modes) and the smoke
  suites pass with the flag on; the default stays `false` until it has seen
  more use.
