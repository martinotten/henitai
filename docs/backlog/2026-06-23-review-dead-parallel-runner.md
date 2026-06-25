# Dead Production Class: ParallelExecutionRunner

Status: open
Date: 2026-06-23
Severity: Medium
Source: 2026-06-23 structured review

## Summary

`Henitai::ParallelExecutionRunner` (153 lines) is autoloaded and has its own
spec, but is never instantiated in production. The execution path uses
`ProcessWorkerRunner` instead. It is dead code carrying a maintained test,
which misleads readers about which runner is live.

## Problem

- `lib/henitai/parallel_execution_runner.rb` — full class, 153 lines.
- `lib/henitai.rb:56`
  `autoload :ParallelExecutionRunner, "henitai/parallel_execution_runner"`.
- `spec/henitai/parallel_execution_runner_spec.rb:5` exercises it.
- The only live runner is `ProcessWorkerRunner`, instantiated at
  `lib/henitai/execution_engine.rb:50`
  `runner = ProcessWorkerRunner.new(worker_count: worker_count(config))`.
- No other `lib/` reference constructs `ParallelExecutionRunner`.

## Fix Plan

1. **Confirm it is truly unused.** `grep -rn ParallelExecutionRunner lib exe`
   — expect only the definition + the autoload line. Check `exe/henitai` and
   any plugin/extension points.
2. **Decide: delete vs. wire.** Default decision = delete. If it was an
   intentional alternate strategy kept for a future config switch, instead add
   a one-line comment documenting that and a backlog note for wiring it — do
   not leave it silently dead.
3. **If delete (red→green is removal-driven):**
   - Remove `lib/henitai/parallel_execution_runner.rb`.
   - Remove the autoload at `lib/henitai.rb:56`.
   - Remove `spec/henitai/parallel_execution_runner_spec.rb`.
   - Run full suite; confirm no constant-missing errors and coverage/mutation
     run is unaffected.
4. Verify the gem still builds and `bundle exec henitai run` works.

## Acceptance

- No dead runner class in `lib/`, or a documented reason it stays.
- Suite green; no dangling autoload or orphan spec.

## Related

- [[2026-06-23-review-reporter-and-runner-class-size]]
