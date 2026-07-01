# Structured Review Findings — 2026-06-23

Status: in progress (2 of 4 done, 2 open, re-verified against code 2026-07-01)
Date: 2026-06-23

Backlog issues from the 2026-06-23 in-depth structured review (multi-agent
across architecture, correctness, tests, hygiene, docs; findings re-verified by
the main agent before capture). Each linked file contains the problem statement
and an embedded fix plan (TDD steps, target files, acceptance criteria).

This round followed the 2026-06-16 review (see
[[2026-06-16-review-index]]); the prior fixes were confirmed to hold with no
regressions.

## Issues by priority

| Sev | Status | Issue | Theme |
|-----|--------|-------|-------|
| Med | done | [[2026-06-23-review-flaky-retry-counter-inflation]] | Correctness — flaky counter bumped before respawn that can fail |
| Med | done | [[2026-06-23-review-dead-parallel-runner]] | Architecture — `ParallelExecutionRunner` autoloaded + spec'd but never used |
| Med | open | [[2026-06-23-review-reporter-and-runner-class-size]] | Architecture — `reporter.rb` (529) + `process_worker_runner.rb` (448) over limit, infra leak |
| Med | open | [[2026-06-23-review-factory-errorpaths-and-tautological-mocks]] | Tests — untested factory `ArgumentError` paths, tautological mock specs |

## Fixed inline during the review (no separate issue)

- Docs: `architecture.md:650` claimed Phase 2 operators "not yet implemented"
  — corrected (all 19 exist since v0.1.3). Phase 2 operator table at line 155
  completed (added `UnaryOperator`, `UpdateOperator`, `RegexMutator`,
  `MethodChainUnwrap`). Front-matter date `March 2026` → `June 2026`.
- Hygiene: `[[2026-06-16-review-lenient-dogfood-config]]` was already done in
  code (`.henitai.yml` `operators: full`, timeout/process_abort enabled) but
  its status marker still said `backlog` — flipped to `done` in the file and
  the 2026-06-16 index.

## Suggested sequencing

1. Quick correctness: flaky-retry-counter-inflation.
2. Architecture: dead-parallel-runner (cheap delete) → reporter-and-runner
   class-size (larger; interlocks with the open 2026-06-16 class-size and
   domain-IO issues — consider doing together).
3. Tests: factory-errorpaths-and-tautological-mocks alongside the arch work.

## Note on validation

One correctness agent flagged a "Critical" nil-timeout crash at
`process_worker_runner.rb:347` (`slot_timeouts.min` → nil passed to wait).
Downgraded after main-agent verification: `IO.select(..., nil)` is legal (blocks
until CHLD), not a type error, and `fill_idle_slots` shifts `pending`
regardless of spawn success so the empty-slots-with-pending state cannot reach
the wait — `done?` guards it. Non-bug; no issue filed. An optional defensive
`|| Float::INFINITY` guard is harmless but not required.
