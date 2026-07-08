# Incremental Verdict Cache (Skip Unchanged Mutants)

Status: done (2026-07-08; see Implementation Decisions below)
Date: 2026-07-06
Severity: Medium
Source: cross-framework comparison against StrykerJS 9.6 (`--incremental`),
PIT 1.25 (`withHistory`), mutmut 3.6 (per-function source hashing) — see
`docs/research/cross_framework_comparison.md` §2.4

## Summary

Three of the four frameworks reviewed reuse prior-run verdicts to skip
re-testing mutants whose context hasn't changed. Henitai already persists
everything needed — `MutantHistoryStore` (SQLite) keys per-mutant status
history by a stable SHA256 identity (ADR-09) — but only ever *reads* it for
the trend report. Every `henitai run` re-executes every in-scope mutant from
scratch, even when neither the subject nor its tests changed.

## Problem

- `MutantHistoryStore#record` writes verdicts; `#trend_report` is the only
  reader (`lib/henitai/mutant_history_store.rb`). No execution-path consumer
  exists.
- `--since origin/main` reduces *scope* (which subjects get mutated) but not
  *work within scope*: a subject touched by a one-line change re-runs all of
  its mutants, including those whose expression/operator/location identity is
  byte-identical to the last run's Killed verdict.
- On the dogfood suite this is the dominant cost for iterative local use:
  change one method, pay for the whole subject's mutant set again.

Prior-art reuse rules (live-verified 2026-07-06):

- **Stryker `--incremental`**: reuse a Killed verdict iff the killing test
  still exists unchanged; reuse Survived iff no new/changed covering test.
  Explicitly documents what it *cannot* see (dependency changes, snapshots).
- **PIT `withHistory`**: bytecode-hash invalidation per class + killing-test
  tracking; docs candidly call the dependency tracking "currently unproven".
- **mutmut**: per-function source hash + git-based detection of non-Python
  dependency changes (`on_dependency_change=warn/rerun/ignore`).

## Proposed Behavior

- Opt-in flag first release: `henitai run --incremental` (mirrors Stryker
  naming). Default behavior unchanged.
- Reuse rule (conservative first cut):
  - A mutant is *reusable* iff its `MutantIdentity.stable_id` matches a
    stored verdict **and** the stored `killing_test` file's content hash is
    unchanged **and** the subject's source (method body) hash is unchanged.
  - Reuse **Killed** verdicts only. Survivors always re-run — they are the
    signal the tool exists for, and Stryker's survived-reuse rule (no new
    covering test) requires test-coverage diffing henitai shouldn't build in
    v1.
- Reused mutants keep status Killed in the report, flagged (e.g. a
  `fromCache: true` extension field next to the existing vendored `stableId`)
  so reports stay honest about what actually executed.
- Terminal summary prints reuse stats: `N of M verdicts reused from history`.
- `--force` (or simply omitting `--incremental`) bypasses the cache.

## Non-Goals

- No survived-verdict reuse in the first release (see above).
- No cross-machine cache sharing (Stryker.NET baseline providers à la S3) —
  the SQLite file in `reports/` is local; CI can cache the directory itself.
- Not replacing `--survivors-from` — that remains the explicit
  "re-check only survivors" workflow; `--incremental` is the inverse
  ("skip proven kills").

## Open Questions

- Test-content hashing: per killing-test *file* hash is cheap but coarse
  (any edit to a large spec file invalidates all verdicts it killed). Finer
  granularity (per-example) needs RSpec/Minitest introspection — defer?
- Interaction with `mutation-history.sqlite3` schema: add columns
  (subject_source_hash, killing_test_hash) via migration, or a separate
  cache table keyed by stable_id? Migration story for existing dogfood DBs
  needed either way.
- Score semantics: MS/MSI computed over reused+executed combined (Stryker
  does this) — should the report also show executed-only scores to detect
  cache-induced drift?
- Flaky interaction: a Killed verdict that originally needed retries — reuse
  or always re-run? (Lean: reuse; the stable verdict is Killed.)

## Implementation Notes

- `lib/henitai/mutant_history_store.rb` — add a verdict-lookup API
  (`killed_verdict_for(stable_id)`); schema change for the two hashes.
- `lib/henitai/mutant_identity.rb` — already provides the stable ID; no
  change expected.
- Natural seam is between mutant generation and execution: where
  `StaticFilter` runs today, an `IncrementalFilter` (same collaborator
  pattern as `MutationSkipDirectives` in `StaticFilter`) can mark mutants
  as cache-hits before `ExecutionEngine` sees them.
- `lib/henitai/cli/options.rb` — new `--incremental` flag following the
  existing `add_*_option` pattern.
- Reporter: `fromCache` extension field beside `stableId`
  (`lib/henitai/reporter.rb` JSON path); terminal summary line.
- Spec seams: `spec/henitai/mutant_history_store_spec.rb` for the lookup
  API; a new `incremental_filter_spec.rb`; end-to-end assertion in the
  rspec smoke fixture (run twice, second run reuses ≥1 verdict).

## Implementation Decisions (2026-07-08)

- **Killing-test hash adapted to covering-tests fingerprint.** Henitai never
  populates `Mutant#killing_test`, so the invalidation basis is the mutant's
  *covering test files* (`covered_by`, the set actually executed against it):
  stored as `covered_tests_fingerprint` (JSON of sorted paths + combined
  content SHA256). Any change/deletion of any covering test invalidates —
  strictly more conservative than Stryker's killing-test rule.
- **Schema**: two nullable columns (`subject_source_hash`,
  `covered_tests_fingerprint`) added to `mutants` via idempotent
  `ALTER TABLE` in `ensure_schema`; legacy rows stay NULL = never reusable.
- **Stable-id ambiguity guard.** MutantIdentity omits coordinates, so
  distinct mutants can share a stable id (observed on the dogfood run: a
  CompileError aliasing a Killed verdict). `IncrementalFilter` skips reuse
  for any id occurring more than once in the run. Root cause filed as
  [[2026-07-08-stable-id-collisions]].
- **Smoke double-run assertion deferred.** The smoke fixtures never produce
  Killed mutants (activation clobbered by the specs' `require_relative` —
  filed as [[2026-07-08-smoke-fixtures-never-kill]]), so there is nothing to
  reuse there. End-to-end verification was done on the dogfood repo instead:
  `henitai run 'Henitai::TestPrioritizer#sort'` twice, second run with
  `--incremental` reused 18 of 19 verdicts with matching scores. Re-add the
  smoke assertion when the fixture ticket lands.

## Fix Plan (TDD)

Prerequisite: a short design spike answering the schema question (add
columns to `mutants` table vs. separate cache table). Default assumption
below: two new nullable columns (`subject_source_hash`,
`killing_test_hash`) on the existing table — nullable makes old rows
valid-but-never-reusable, which is the correct conservative behavior.

**Phase 1 — store:**

1. **Red.** `mutant_history_store_spec.rb`: opening a database created
   with the current schema and calling any API migrates it in place
   (new columns exist, existing rows/history intact — fixture DB checked
   into `spec/fixtures/`).
2. **Green.** Additive `ALTER TABLE` in `ensure_schema`
   (`lib/henitai/mutant_history_store/sql.rb`), guarded by a
   column-existence check.
3. **Red.** `#record` persists both hashes for killed mutants (source
   hash of the subject's method body, content hash of the killing test
   file); non-killed rows leave them NULL.
4. **Red.** New `#killed_verdict_for(stable_id)` returns
   `{status:, subject_source_hash:, killing_test_hash:}` for killed rows
   with non-NULL hashes; nil for survivors, unknown IDs, and legacy rows.
5. **Green** both; refactor.

**Phase 2 — filter:**

6. **Red.** New `incremental_filter_spec.rb`, decision matrix per mutant:
   - matching stable_id, both hashes unchanged → marked cache-hit
   - subject source changed → runs
   - killing-test file changed (or deleted) → runs
   - stored verdict not Killed → runs
   - no history row / legacy row without hashes → runs
7. **Green.** `IncrementalFilter` (collaborator injected into the
   pipeline where `StaticFilter` runs, same pattern as
   `MutationSkipDirectives`); cache-hits get status Killed +
   `from_cache` flag on the mutant.
8. **Red.** `runner_spec.rb`: with `--incremental`, `ExecutionEngine`
   receives only non-cached mutants; without the flag, filter is never
   constructed (default path untouched).
9. **Green.** Runner wiring behind the flag.

**Phase 3 — CLI + reporting:**

10. **Red.** `options_spec`: `--incremental` and `--force` parse;
    `--force` with `--incremental` bypasses reuse.
11. **Red.** Reporter specs: JSON emits `fromCache: true` beside the
    vendored `stableId` for reused mutants; terminal summary prints
    `N of M verdicts reused from history`; MS/MSI computed over the
    combined (reused + executed) set.
12. **Green** all; refactor, rubocop, steep, full suite.

**Phase 4 — end-to-end:**

13. Smoke fixture: run twice with `--incremental`; assert second run's
    JSON report contains ≥1 `fromCache: true` mutant and the summary
    line, and that total mutant counts/score match run one.

## Acceptance

- Opt-in only: without `--incremental`, behavior and report output
  byte-identical to today (existing specs unmodified).
- Only Killed verdicts are ever reused; Survived/Timeout/errors always
  re-execute.
- Reuse invalidated by any of: subject source change, killing-test file
  change/deletion, missing or legacy history row.
- Reused mutants visible in the report (`fromCache: true`), counted in
  MS/MSI, summarized in the terminal (`N of M verdicts reused`).
- Existing `mutation-history.sqlite3` files migrate transparently, no
  data loss (fixture-DB proof).
- `--force` restores full execution; `--survivors-from` completely
  unaffected (its spec set untouched).
- Flaky interaction per ticket decision: previously-retried Killed
  verdicts are reused like any other Killed verdict.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | store: migration from fixture DB, hash persistence, `killed_verdict_for` matrix (killed/survivor/unknown/legacy) |
| Unit | `incremental_filter_spec.rb`: full 5-case decision matrix |
| Unit | runner: engine receives filtered set; default path never builds the filter |
| Unit | CLI options (`--incremental`, `--force`); reporter JSON `fromCache` + terminal summary; scoring over combined set |
| Smoke | double-run reuse assertion (rspec fixture); minitest fixture single run unaffected |
| Regression | full dogfood run without the flag — identical output; `--survivors-from` smoke path green |
