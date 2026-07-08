# Dry-Run Mode (List Mutants Without Executing Tests)

Status: done (2026-07-08)
Date: 2026-07-06
Severity: Low
Source: cross-framework comparison — StrykerJS 9.6 (`dryRunOnly: true`),
PIT 1.25 (`dryRun` param: "gather coverage for all tests, and generate all
mutants, without running any tests against the mutants"), cargo-mutants
(`--list`) — see `docs/research/cross_framework_comparison.md` §2.7

## Summary

Three frameworks offer a mode that runs the pipeline up to (but not
including) mutant execution, so users can inspect what *would* run — which
subjects resolve, which mutants get generated, what static/arid/skip
filtering removes — without paying for test execution. Henitai has
`henitai operator list` (static operator catalog) but no way to preview the
actual mutant set for a given run configuration.

## Problem

Today the only way to answer "what will `henitai run --since origin/main`
actually do?" is to run it. That makes several workflows needlessly
expensive:

- Tuning `ignore_patterns` / `# henitai:disable` placement: each iteration
  costs a full mutation run to see whether the mutant disappeared or became
  Ignored.
- Debugging "0 mutants generated" incremental runs in CI (this bit us:
  see `docs/backlog/done/2026-06-16-cli-empty-mutant-set-exit.md`) — a
  dry-run would show the empty resolution instantly.
- Estimating run cost before committing to it (`mutants.size ×
  avg-test-time` is a good enough forecast; cargo-mutants users use
  `--list` for exactly this).

## Proposed Behavior

- `henitai run --dry-run [other flags]`: execute Gates 0–3 as normal
  (coverage check, subject resolution, mutant generation, static/skip/arid
  filtering) and stop before execution (Gate 4).
- Output: per-subject mutant listing — operator, description,
  `file:start_line`, and post-filter status (`pending` vs. `ignored` with
  the filter reason). Summary line with total counts per status.
- Exit code 0 always (nothing was tested; there is no score to gate on) —
  consistent with the empty-mutant-set exit-0 decision.
- Composes with everything that shapes the mutant set: `--since`,
  `--operators`, subject patterns, `--survivors-from`.

## Non-Goals

- Not a coverage-only run (Stryker's `dryRunOnly` also validates the initial
  test run; henitai's Gate 0 already does that implicitly — if coverage
  bootstrap is needed it still happens, since subject resolution requires
  it).
- No JSON output in the first release — terminal listing only; a
  `--dry-run` + json reporter combination can follow if needed.

## Open Questions

- Flag placement: `henitai run --dry-run` (composes with all run flags for
  free) vs. a separate `henitai list` subcommand (cargo-mutants style,
  cleaner conceptually but duplicates option parsing). Leaning: flag on
  `run`, since the whole value is "same config, minus execution".
- Should stillborn filtering (`StillbornFilter`, needs a syntax check per
  mutant) run in dry-run mode? It's cheap relative to tests but not free;
  including it makes the preview exact. Leaning: include.

## Implementation Notes

- `lib/henitai/runner.rb` — the 6-gate order makes this a clean early
  return between Gate 3 and Gate 4; dry-run assembles a listing from the
  already-built mutant collection instead of calling `ExecutionEngine`.
- `lib/henitai/cli/options.rb` — `add_dry_run_option` following the
  existing pattern; `lib/henitai/cli/run_command.rb` — exit 0 path.
- Reuse `Reporter::Terminal`'s formatting helpers where possible rather
  than a new formatter class (check `format_row` / listing helpers in
  `lib/henitai/reporter.rb`).
- Specs: `runner_spec.rb` (stops before execution — assert
  `ExecutionEngine` never receives `run`), `cli/run_command` spec for flag +
  exit code, one smoke-fixture assertion (dry-run output lists ≥1 mutant,
  no test process spawned).

## Decisions (resolving the Open Questions)

- **Flag on `run`** (`henitai run --dry-run`), not a separate subcommand —
  composes with `--since`/`--operators`/patterns/`--survivors-from` for
  free.
- **Stillborn filtering included** — the preview must be exact.
- **No report files written.** Dry-run must not touch `reports/` — in
  particular it must not overwrite an existing `mutation-report.json`
  (which `--survivors-from` consumes) or record into
  `mutation-history.sqlite3`. Terminal output only.

## Fix Plan (TDD)

1. **Red.** `options_spec`: `--dry-run` parses into
   `options[:dry_run]`.
2. **Green.** `add_dry_run_option` in `lib/henitai/cli/options.rb`.
3. **Red.** `runner_spec.rb`: with `dry_run: true`,
   - `ExecutionEngine` never receives `run` (message expectation on the
     injected engine),
   - `MutantHistoryStore` never receives `record`,
   - no reporter other than the dry-run listing runs (no JSON/HTML files
     written into a tmpdir `reports_dir`),
   - the returned listing contains all post-Gate-3 mutants with status
     `pending` or `ignored` (+ filter reason for ignored ones).
4. **Green.** Early return in `lib/henitai/runner.rb` between Gate 3
   (filtering) and Gate 4 (execution); Gates 0–3 run exactly as today
   (coverage gate still enforced — a dry run on an uncovered project
   still raises `Henitai::CoverageError`).
5. **Red.** Listing-output spec: per-subject grouping, one line per
   mutant (`operator — description  file:start_line  [status]`), summary
   counts per status. Reuse `Reporter::Terminal` formatting helpers
   (`format_row` etc.) rather than a new formatter class where they fit.
6. **Green**, refactor.
7. **Red.** `cli/run_command` spec: `--dry-run` exits `0` regardless of
   mutant counts (including the zero-mutant case — consistent with the
   empty-set exit-0 decision) and regardless of `thresholds`.
8. **Green**, rubocop, steep, full suite.

## Acceptance

- `henitai run --dry-run` prints the exact post-filter mutant set
  (including Ignored entries with reasons) and executes zero tests — no
  child processes forked for mutants.
- Gate 0 unchanged: missing/stale coverage still bootstraps (or aborts
  with `CoverageError`) exactly as in a real run.
- `reports/` untouched: no `mutation-report.json`, no HTML, no SQLite
  write, no `mutation-logs/` child logs.
- Exit code always `0`; thresholds not evaluated.
- Composes with `--since`, `--operators`, subject patterns and
  `--survivors-from` (listing reflects the narrowed set).
- Zero-mutant dry-run prints an empty listing + summary, exits `0`.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | option parsing; runner early-return (engine/history/reporter message expectations + tmpdir file assertions); exit-code spec incl. zero-mutant case |
| Unit | listing format spec (grouping, line format, ignored-with-reason, summary counts) |
| Integration | composition cases: `--dry-run --since <ref>` and `--dry-run --operators full` produce differently-sized listings (runner spec with fixture subjects) |
| Smoke | rspec fixture: `henitai run --dry-run` lists ≥1 mutant, `reports/mutation-report.json` absent afterwards, exit 0 |
| Regression | normal run (no flag) byte-identical; `henitai clean` spec unaffected |
