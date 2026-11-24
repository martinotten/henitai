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
  the spec double that faked it are gone. Persisted cross-run kill counts
  were not added: the history store keeps no killing test files.
- Found while fixing: with `config.order = :random` (this repository's own
  spec_helper) the RSpec child reshuffled the top-level groups, so no file
  order ever took effect. `RspecFileOrder` sorts the groups by the order of
  the mutant's test files. Minitest shuffles classes; left as is.
