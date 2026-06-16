# Remove Timing- and chdir-Dependent Flakiness From Specs

Status: backlog
Date: 2026-06-16
Severity: Medium
Source: 2026-06-16 structured review

## Summary

Several specs synchronize concurrent behavior with `sleep` and mutate global
process state with `Dir.chdir`. AGENTS.md requires fast, independent, repeatable
tests. These will flake under CI load and block future parallelization (the
suite runs `config.order = :random`).

## Problem

- `spec/henitai/parallel_execution_runner_spec.rb` and
  `spec/henitai/process_worker_runner_spec.rb` use `sleep 0.01`–`sleep 0.05` to
  coordinate concurrent behavior. Timing-based sync flakes on slow/loaded CI.
- `spec/henitai/cli_spec.rb` uses `Dir.chdir` in an `around` block plus nested
  `Dir.chdir` calls (lines ~563, 580, 801). `Dir.chdir` mutates global,
  non-thread-safe process state; unsafe with random order and any future
  parallel test execution.

## Fix Plan

1. **Replace sleeps with deterministic synchronization.** Use explicit
   readiness signals — a `Queue`, condition variable, or polling on an
   observable state change with a bounded timeout — instead of fixed `sleep`.
   Where a real subprocess is needed, wait on a pipe/IO readiness rather than a
   wall-clock guess.
2. **Isolate working directory.** Replace `Dir.chdir` with passing an explicit
   base/working directory into the code under test, OR wrap each example in
   `Dir.mktmpdir` and pass the path as an argument rather than changing global
   cwd. If `chdir` is unavoidable for a CLI integration test, scope it as
   tightly as possible and document why.
3. **Confirm independence.** Run the affected specs repeatedly with a fixed and
   then varied seed; confirm no order dependence.

## Acceptance

- No `sleep`-based synchronization in the parallel/process-worker specs.
- `cli_spec.rb` does not mutate global cwd (or does so only in a documented,
  tightly-scoped block).
- Affected specs pass under repeated random-order runs.

## Related

- [[2026-06-16-review-test-overmocking-and-gaps]]
