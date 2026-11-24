# Kill History Never Reaches `TestPrioritizer`

Status: done (2026-11-24)
Date: 2026-11-23
Severity: Medium (wall-clock per killed mutant; no verdict impact)
Source: review of PR #55 (fail-fast in the mutant child)

## Summary

`TestPrioritizer` orders a mutant's test files by kill-history count first
and runtime second, so that the test most likely to kill runs first. Its
history comes from `ExecutionEngine#test_history`
(`lib/henitai/execution_engine.rb`), which reads `config.history`.
`Configuration` defines no `history`, so the method always returns `{}` and
ordering falls back to runtime alone.

## Why It Matters Now

Since a mutant child stops at its first failure
([`2026-11-12-child-fail-fast.md`](2026-11-12-child-fail-fast.md)), test
order decides how much of a killed mutant's run is skipped. A file that
killed neighbouring mutants of the same subject is the best first guess.

## Fix Sketch

- Decide the source: per-test-file kill counts from this run (the
  `killing_tests` of finished results, updated as the run goes) and/or from
  `MutantHistoryStore`.
- Feed it to `TestPrioritizer` through an explicit collaborator instead of a
  duck-typed `config.history`; remove the `respond_to?` guard.
- Minitest shuffles test classes by seed inside the child, so ordering only
  affects RSpec unless the Minitest child also orders classes by file.

## Test Plan

- Engine spec: a test file that killed an earlier mutant is passed first for
  the next mutant of the same subject.
- Measure dogfood wall time before/after as in the fail-fast item.

## Resolution

- `KillHistory` (progress observer behind the `ControlGate`) counts final
  kills per test file during the run; `ExecutionEngine` hands it to
  `TestPrioritizer` for every mutant still to launch. `config.history` and
  the spec double that faked it are gone.
- Found while fixing: with `config.order = :random` (this repository's own
  spec_helper) the RSpec child reshuffled the top-level groups, so no file
  order ever took effect, neither kill counts nor the runtime tiebreaker.
  `RspecFileOrder` sorts the groups by the order of the mutant's test files;
  RSpec's ordering still applies within a file. Minitest shuffles classes;
  left as is.
- Kill counts alone made runs slower (measurement below). A mutant child now
  writes the test file it is running next to its report (`<report>.running`,
  `ChildReportStore#write_running`, fed by `TestFileOutcomes#started` from
  RSpec group starts and Minitest `prerecord`). A `Timeout` result carries
  that file as `hanging_test`; `KillHistory` remembers it per subject, and
  `TestPrioritizer` sorts such files last, ahead of kill count and runtime.

## Analysis (2026-11-24)

Dogfood `SlotScheduler*` subjects, 408 mutants unsampled, `jobs: 1`,
`mutation.timeout: 10`, fail-fast already on main. Runs interleaved.

| Ordering | Wall time | Timeouts | Killed |
|---|---|---|---|
| main (RSpec random order) | 639, 430, 449, 462 s | 36-40, 32, 39 | 345-353 |
| kill count first | 923, 801 s | 74 | 311 |
| runtime only (fastest first) | 929, 801 s | 70, 73 | 312-315 |
| hang-aware (shipped) | 359, 248 s | 16, 12 | 369, 359 |

- Survivors are identical (23) in every run; only Killed/Timeout move.
- Any fixed order without the hang rule is about twice as slow as random
  order. All 40 mutants that went from Killed to Timeout under kill-count
  ordering ran `process_worker_runner_spec.rb` first: it has the most kills
  in the run but hangs under mutants of the scheduler's drain code before
  any example fails, so every such mutant waits out the 10 s timeout. With
  random order a quickly failing file often runs first.
- Timeouts were common before any of this: 82 of the 408 mutants timed out
  before fail-fast (a test killed the mutant, a later one hung). Fail-fast
  made order matter: the run ends at the first failure, so it pays only if
  a failing file comes before the hanging one.
- Hang-aware ordering pays the hang once per subject and file: versus main,
  24 and 28 mutants went from Timeout to Killed, 8 and 6 the other way.
- The second hang-aware run also had 14 CompileError: one subject's control
  child died by SIGTERM. Not reproduced; tracked in
  [`2026-11-24-control-child-terminated-by-sigterm.md`](2026-11-24-control-child-terminated-by-sigterm.md).
- One runtime-only measurement was discarded: the variant was built by
  disabling kill counts in a worktree while its spec for kill ordering still
  ran, so every control including that spec failed (256 CompileError). A
  variant must keep its own suite green.

## Follow-ups (2026-11-24)

- Cross-run persistence: `reports/henitai_test_order.json` keeps kill
  counts (latest run's count per file) and hangs (accumulated per subject);
  `henitai clean` removes it. Same 408 mutants, three runs in a row
  starting without the file: 318 s (learning, 14 timeouts), then 150 s and
  180 s (7 and 10 timeouts). Survivors identical (23).
- Real-child spec for the Minitest running-file marker
  (`minitest_failed_tests_process_spec.rb`).

## Not Done

- Minitest ordering: Minitest shuffles its test classes itself.
