# `CoverageBootstrapper` Only Checks Freshness, Never Completeness — Scoped Runs Silently Mark Everything `NoCoverage`

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered running `henitai run 'Henitai::Integration::ChildDebugSupport*'` scoped to a
module never covered by a prior scoped run

## Summary

`CoverageBootstrapper#ensure!` (`lib/henitai/coverage_bootstrapper.rb`)
decides whether to re-bootstrap coverage purely by **mtime freshness**
(`coverage_fresh?`, `per_test_coverage_fresh?` → `watched_files_fresh?`,
lines 67-73 and 137-143) plus mere **existence**
(`per_test_coverage_available?`, line 145-147). It never checks whether
`reports/henitai_per_test.json` actually **contains entries for the
source/test files the current invocation cares about**. A per-test
coverage file left over from an earlier *scoped* run — which by design
only records coverage for the files exercised in that scope — reads as
"fresh and available" for a completely different, unrelated scoped run,
so the bootstrap is skipped and every mutant in the new scope is marked
`NoCoverage` without a single test executing.

Reproduced directly: after a scoped run touching only `cli_spec.rb`, the
resulting `reports/henitai_per_test.json` contained a single top-level
key (`./spec/henitai/cli_spec.rb`). Running
`henitai run 'Henitai::Integration::ChildDebugSupport*'` afterwards
returned in 0.37s — Killed 0, Survived 0, No coverage 172 — because
`per_test_coverage_ready?` was satisfied by that unrelated file's mtime
and existence, so no test suite ever ran for this invocation.

## Problem

- `per_test_coverage_ready?` (line 149) short-circuits to `true` on
  freshness + existence alone; it has no notion of "does this JSON's
  key set cover the source files I resolved for this subject pattern."
- `coverage_available?` (line 42) does check `static_filter.coverage_lines_for(config)`
  against `source_files`, but that reads `.resultset.json` (the
  aggregate SimpleCov coverage across the whole configured `includes`,
  not the per-test map) — a full prior run can make this pass globally
  even while the per-test map used for test *selection* is scoped-thin.
- The failure mode is silent: no warning, no error, just an
  instant `NoCoverage`-only report that looks superficially like "ran
  fine, nothing to kill." A user unfamiliar with the internals reads
  `Duration 0.37s` and might not notice no tests ran at all.
- Workaround today is `henitai clean` (nukes all report/coverage
  artifacts) followed by a full-suite bootstrap — correct but wasteful
  when only the per-test map is thin, and non-obvious (nothing tells
  the user this is what's wrong).
- Related but distinct from the two other reporting gaps already filed:
  - `docs/backlog/2026-07-08-partial-run-report-overwrite.md` — the
    *output* report (`mutation-report.json`) loses prior findings on a
    scoped run.
  - `docs/backlog/2026-07-06-incremental-verdict-cache.md` — the
    SQLite verdict cache (`mutation-history.sqlite3`) already merges
    correctly per mutant ID; not a coverage-completeness problem.
  - This ticket is about the *input* gate: `henitai_per_test.json`
    itself needs a completeness check, and ideally should be additive
    across scoped runs the same way the SQLite store already is,
    rather than being freshness-gated only.

## Fix Sketch

See `docs/backlog/2026-07-08-per-test-coverage-completeness-check-plan.md`
for the detailed, reviewed implementation plan — it corrects a
convergence hazard in sketch #1 below (naive superset-checking against
*all* configured source files forces a full re-bootstrap on every run
for any project with an uncovered lib file) in favor of a full-run
provenance manifest. The two-change shape below is still directionally
right; the linked plan is authoritative on mechanism.

Two complementary changes:

1. **Detect staleness correctly.** `per_test_coverage_ready?` should
   additionally verify the per-test JSON's file-key set is a superset
   of the resolved `source_files` for the current subject pattern (or,
   more precisely, that at least the files touched by the resolved
   subjects appear as keys with non-empty test lists). If not, treat it
   as not-ready and re-bootstrap — same code path as today's freshness
   failure, just a new condition alongside `coverage_fresh?`.
2. **Make the per-test map additive instead of scope-replacing**, so
   running a scoped subject doesn't leave the file permanently thin for
   everything else. When `PerTestCoverageCollector`/whatever writes
   `henitai_per_test.json` runs for a scoped invocation, merge new
   entries into the existing file's keys instead of overwriting the
   whole document — mirroring the pattern `MutantHistoryStore` already
   uses (`lib/henitai/mutant_history_store.rb:104`, upsert by key) that
   the `mutation-report.json` writer (per the other ticket) should also
   adopt. This turns "coverage exists but is scoped-thin" into "coverage
   accumulates as you run more scopes over a session," which is exactly
   the iterative workflow (fix one file's survivors, run scoped,
   move on) this was blocking.

Either change alone fixes the reported symptom (correctness); doing both
also fixes the wasted-bootstrap cost for anyone routinely running
scoped subjects across a session.

## Test Plan

- `CoverageBootstrapper` spec: per-test coverage file exists, is fresh
  (mtime), but its keys don't cover the resolved source files for this
  run → bootstrap still triggers.
- Same file, keys *do* cover the resolved source files → bootstrap
  skipped (no regression to the fast path).
- Per-test coverage writer spec: running scope A then scope B leaves
  both A's and B's entries present in `henitai_per_test.json` (merge,
  not replace).
- Regression: full unscoped run still produces a complete/accurate
  per-test map (merge logic doesn't leave stale entries for files that
  no longer exist or were renamed — needs an explicit prune-on-full-run
  path or a documented limitation).
