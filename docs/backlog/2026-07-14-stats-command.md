# `henitai stats` Command

Status: proposed
Date: 2026-07-14
Severity: Low (insight tooling)
Source: manual per-operator survival analysis over the henitai dogfood
report and a real Rails app (evently, 2026-07-14) — both analyses required
ad-hoc Python over `mutation-report.json`; the evently numbers directly
motivated the hard operator set (ADR-12).

## Summary

A read-only `henitai stats` command that answers "where does my mutation
noise and signal come from?" from the artifacts henitai already writes
(canonical report, history sqlite, per-test coverage). No new data
collection — only aggregation.

## Proposed subcommands / views

- `henitai stats operators` (the motivating case): per-operator totals,
  killed/survived/ignored/no-coverage/compile-error counts, and survival
  rate over the effective denominator; sorted by survival rate. Optionally
  `--suggest`: flag operators whose survival rate exceeds a threshold as
  hard-set/demotion candidates — data-driven set curation instead of
  ADR debates. Real-world reference numbers from evently: HashLiteral 37%
  survival (86% of which were symbol->string key mutants), light-set
  operators all ≤2.8%.
- `henitai stats files`: per-file survivor counts and score — where to
  spend test effort next.
- `henitai stats trend`: score/survivor development over runs from
  `mutation-history.sqlite3` (days_alive, latent mutants, newly-killed).
- `henitai stats reuse`: incremental cache effectiveness — reused vs
  executed per run, invalidation causes if recorded.
- `henitai stats flaky`: retry statistics per mutant/test (flaky-retry
  counts are already tracked).
- `henitai stats descriptions`: survivor counts grouped by mutation
  description (e.g. "replaced symbol key with string key" 69x) — the
  fastest way to spot a systematic noise class.

## Design notes

- Read-only over `reports/mutation-report.json` +
  `reports/mutation-history.sqlite3`; respects `reports_dir`; exits 2 with
  a clear message when artifacts are missing.
- Caveat to surface in output: the canonical report merges scoped runs, so
  entries can be stale relative to HEAD (observed: pre-activator-fix
  phantom survivors in module_function files skewed operator stats until
  the subjects were re-run). Show each mutant's last-seen recency where
  available, or an aggregate "N verdicts older than the newest full run".
- History store currently has no operator column (identity is hashed) —
  operator/description aggregation reads the JSON report; trend views read
  sqlite. If per-operator trend is wanted later, add an operator column to
  the mutants table (additive migration, same pattern as the verdict-cache
  columns).
- Output: terminal table by default, `--format json` for tooling.

## Acceptance (first slice: `stats operators`)

- `henitai stats operators` prints the table for the configured
  reports_dir; matches the numbers derivable from the JSON report.
- Denominator excludes Ignored/NoCoverage/CompileError (consistent with MS).
- Stale-verdict caveat line appears when the report predates HEAD.
- Read-only: no artifact is modified; exits 0.
