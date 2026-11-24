# Control Child Terminated by SIGTERM

Status: probable cause fixed (2026-11-24); watch for recurrence
Date: 2026-11-24
Severity: Medium (rare; fails safe, but turns a subject's detections into
`CompileError` and lowers the score)
Source: measurement for
[`2026-11-23-kill-history-never-reaches-test-prioritizer.md`](2026-11-23-kill-history-never-reaches-test-prioritizer.md)

## Observation

In one of about 14 measured dogfood runs (`SlotScheduler*`, 408 mutants,
`jobs: 1`, branch `fix/kill-history-prioritization` at 43ebb4e, hang-aware
ordering), the control run of one subject (`lib/henitai/slot_scheduler/draining.rb:29`)
failed with:

```text
control run failed: the unmutated method fails its tests when injected
(runtime_error: child terminated by signal SIGTERM)
```

All 14 detected mutants of that subject were reclassified as
`CompileError`. Its test files, in run order: `slot_scheduler/draining_spec.rb`,
`process_worker_runner_spec.rb`, `slot_scheduler_spec.rb`,
`slot_scheduler/retry_policy_spec.rb`, `execution_engine_spec.rb`.

## Why It Is Not a Timeout

A control job that exceeds its timeout goes through `Draining`, and
`DrainVerdict` labels it `:timeout` after the parent's SIGTERM. A result of
"terminated by signal SIGTERM" means the child was reaped with a signaled
status outside that path, so the signal did not come from the timeout
handling.

## What Was Tried

- The five spec files, run standalone 16 times (random and defined order,
  also as process-group leader like a mutant child): all green.
- No spec in those files sends an unstubbed signal (`Process.kill` is
  stubbed in `process_worker_runner_spec.rb`).
- It never appeared on main or in the other variants' runs; whether the
  hang-aware ordering (fixed file order, `<report>.running` marker) plays a
  part is open.

## Reproduction Attempt (2026-11-24)

Five more runs on main d3e7a11 (hang-aware ordering, same 408 mutants,
`HENITAI_DEBUG_CHILD=1 HENITAI_DEBUG_SCHEDULER=1`, reports kept on any
control failure): no control failure, 239-309 s each. Together with the
earlier measurements the failure was seen once in about 19 runs, so it is
rare and not tied to the hang-aware ordering in any visible way.

## Probable Cause (2026-11-24)

Two process-free specs sent real signals to fake pids, and process-free
specs run inside mutant and control children during henitai's own runs:

- `spec/henitai/slot_scheduler_spec.rb`: `build_host` defaulted to the real
  `ProcessWorkerRunner::Runtime` while the fake integration handed out pids
  1000, 1001, ...; completing a slot sent SIGTERM (and possibly SIGKILL) to
  process group -1000, falling back to pid 1000.
- `spec/henitai/fork_server/client_spec.rb`: "completes outstanding processes
  as lost" let `GroupKiller.kill` send SIGKILL to process group -99.

A control child is the leader of its own process group, so when its pid
happened to equal one of those fake pids, a spec running in a sibling child
sent it SIGTERM: "child terminated by signal SIGTERM", outside the timeout
path, rare. The same spec failed PR #58's CI with `Errno::EPERM` when pid
1000 belonged to another user.

Fixed on branch `fix/specs-never-signal-foreign-processes`: the process guard
behind `bin/verify-process-free-specs` now blocks `Process.kill` except
signal 0 and signals to the spec process itself, and both specs use a
recording runtime or a stubbed `GroupKiller`.

## Next Steps

- Keep the debug switches available for long dogfood runs and keep the
  reports directory when `control runs failed` appears, so the next
  occurrence comes with the control child's log.
- Check who can signal the control child's process group: other slots'
  `tear_down_process_group` (pid/pgid reuse), the drain path's
  `prune_raced_draining_slots`, and specs of the scheduler run inside the
  child that drive a real `ProcessWorkerRunner` signal path.
