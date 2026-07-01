# Dead Production Class: ParallelExecutionRunner

Status: done
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

1. **Confirm it is truly unused.** `grep -rn ParallelExecutionRunner` — done:
   only the class definition, the autoload line, its own spec, `CHANGELOG.md`
   history, and doc mentions in `CLAUDE.md`. No production caller.
2. **Decide: delete vs. wire.** Default decision = delete. — decided: delete,
   confirmed dead in favor of `ProcessWorkerRunner`/`SlotScheduler`.
3. **Delete (red→green is removal-driven):** — done.
   - Removed `lib/henitai/parallel_execution_runner.rb`.
   - Removed the autoload in `lib/henitai.rb`.
   - Removed `spec/henitai/parallel_execution_runner_spec.rb`.
   - Also removed the now-dangling `require_relative "parallel_execution_runner"`
     in `lib/henitai/execution_engine.rb` (not mentioned in the original plan,
     but the delete would otherwise `LoadError` at require time).
   - Updated stale `CLAUDE.md` references (module table row, execution-model
     bullet) that still named `ParallelExecutionRunner` instead of the live
     `ProcessWorkerRunner`.
   - Full suite green (1125 examples, down from 1128 — the removed spec file's
     3 examples), rubocop clean (197 files), steep clean.
4. Verify the gem still builds and `bundle exec henitai run` works. — done:
   `bundle exec henitai run 'Henitai::ExecutionEngine#run'` completes normally
   (MS 100.00%, no framework errors).

## Acceptance

- No dead runner class in `lib/`, or a documented reason it stays. — met.
- Suite green; no dangling autoload or orphan spec. — met.

## Related

- [[2026-06-23-review-reporter-and-runner-class-size]]
