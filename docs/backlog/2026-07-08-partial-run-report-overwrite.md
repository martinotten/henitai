# Scoped/Partial Runs Overwrite the Canonical Report Instead of Merging

Status: done (2026-07-09)
Date: 2026-07-08
Severity: Medium
Source: discovered while fixing survived mutants in `AvailableCpuCount` with a subject-scoped run

## Summary

`henitai run 'Foo::Bar*'` (or any subject-pattern-scoped run, including
`--survivors-from`) fully replaces `reports/mutation-report.json` with a
schema built only from the mutants executed in that invocation. Findings
for every file/class outside the current scope silently disappear from
the report on disk, even though they're still true.

This is distinct from `docs/backlog/2026-07-06-incremental-verdict-cache.md`:
that ticket is about `MutantHistoryStore` (SQLite) letting `--incremental`
skip re-executing unchanged mutants — it assumes the run still covers
everything in scope and just skips execution. This ticket is about the
JSON/HTML report *file* losing prior results for files not touched by the
current run at all.

## Problem

- `Reporter::Json#report` (`lib/henitai/reporter.rb:267`) calls
  `result.to_stryker_schema` and `write_canonical`
  (`lib/henitai/reporter.rb:277-280`) does an unconditional
  `File.write(canonical_path, JSON.pretty_generate(schema))` —
  `canonical_path` = `reports/mutation-report.json`.
- `schema` comes from `Result#to_stryker_schema` →
  `build_files_section` (`lib/henitai/result.rb:133`), which does
  `mutants.group_by { |m| m.location[:file] }` over only the current
  run's `@mutants`. Nothing reads the prior report or merges its `files`
  entries.
- `Reporter::Html#report` (`reporter.rb:343-346`) has the same
  unconditional-overwrite shape.
- `--survivors-from` reruns a specific survivor subset and marks the
  schema `partialRerun: true`, but still overwrites the canonical file
  wholesale — prior mutants not in the rerun set vanish from disk too.
- This makes it awkward to work through findings file-by-file or
  class-by-class across sessions: fixing one file's survivors and running
  a scoped verification pass destroys the last full-run's record for
  everything else, so there's no persistent "figure out what's left"
  view without rerunning the whole suite.

## Fix Sketch

See `docs/backlog/2026-07-08-partial-run-report-overwrite-plan.md` for
the detailed, reviewed implementation plan. It corrects the concern
below about recomputing aggregate stats (the canonical JSON schema
carries no aggregate score/counts at all — `Result#base_schema` only
emits `schemaVersion`/`sessionId`/`thresholds`/`files`, so merging
`files` is a complete fix, nothing to recompute) and settles on
**mutant-level (`stableId`) merge, not file-level** — file-level would
silently drop a file's untouched mutants during a `--survivors-from`
rerun that only re-verifies some of that file's mutants.

Give `write_canonical` (and the HTML writer) a merge step: if
`reports/mutation-report.json` already exists, load it, and for each file
key present in the *current* run's schema, replace that file's entry;
leave every other file's entry untouched. Union the results before
writing. Aggregate top-level stats (`mutationScore`, thresholds, etc.)
would need recomputing from the merged mutant set rather than the
current run's subset alone — probably the simplest correct approach is:
merge at the mutant level (keyed by the existing stable mutant identity
used by `MutantHistoryStore`), then rebuild the whole `Result`/schema
from the merged mutant list rather than patching the serialized JSON
directly.

Needs an opt-in/out: full (`--since`-less, unscoped) runs should probably
still fully replace the report (an unscoped run *is* authoritative for
everything), while subject-pattern-scoped runs and `--survivors-from`
should merge. Might be simplest to gate on "did this run's subject
resolution cover 100% of configured `includes`."

## Test Plan

- Report writer spec: run A covers file X, run B (scoped to file Y only)
  should produce a merged report containing both X's and Y's mutants,
  with X's entries unchanged from run A.
- Full/unscoped run still replaces everything (no stale entries from a
  previous scoped run linger after a full run).
- `--survivors-from` rerun: unaffected files keep their prior entries;
  rerun mutants' entries update in place.
- HTML reporter gets the same merge behavior (or explicitly documented
  as JSON-only if scoping the fix).

## Resolution (2026-07-09)

Implemented per the plan: new `Henitai::CanonicalReportMerger` (pure,
`stableId`-keyed, fail-safe — any anomaly, including a merge that would end
up thinner than the current run alone, falls back to the current schema
alone). `Result#authoritative?` (default `true`) and `Runner#full_run?`
(`pattern_subjects.empty? && @since.nil? && !survivor_rerun?`) gate whether
`Reporter::Json`/`Html` fully replace `mutation-report.json` or merge into
it; session snapshots and activation recipes stay current-run-only as
planned. Both reporters share the merge via `Reporter::Base`.

Verified end-to-end on the dogfood repo: two sequential subject-scoped runs
(`CanonicalReportMerger`, then `Result*`) grew the canonical report from 2
files/277 mutants to 3 files/594 mutants, with the first run's files
byte-unchanged — no data lost across scoped runs.
