# Implementation Plan: Merge Canonical Report on Scoped/Partial Runs

Status: plan (designed by an Opus subagent, informed by the per-test-coverage
completeness verification pass)
Parent ticket: `docs/backlog/2026-07-08-partial-run-report-overwrite.md`
Date: 2026-07-08

## Citation corrections vs. the parent ticket

- `Reporter::Json#write_canonical` unconditional write: `reporter.rb:277-280`
  (the `File.write` itself is line 279) — parent ticket's line numbers
  confirmed close enough, verified exact here.
- `canonical_path` = `reports_dir/mutation-report.json`: `reporter.rb:318-320`. Confirmed.
- `Reporter::Html#report` same unconditional-overwrite shape: `reporter.rb:343-346`. Confirmed.
- `Result#to_stryker_schema` at `result.rb:109`; `build_files_section` is
  actually at **`result.rb:137`** (`group_by` at line 138) — the parent
  ticket cites line 133, off by a handful of lines. Substance unchanged.
- **Load-bearing correction the parent ticket's Fix Sketch got wrong:**
  `base_schema` (`result.rb:122-129`) emits only `schemaVersion`,
  `sessionId`, `thresholds`, `files` (+ `gitSha`, and for partial reruns
  `partialRerun`/`unmatchedSurvivorIds`). **The canonical JSON carries no
  top-level `mutationScore`/kill-counts/equivalence-uncertainty at all.**
  Those numbers exist only in the terminal reporter (computed live,
  per-run) and the history SQLite (`mutant_history_store.rb:200-215`).
  `mutation-testing-elements` recomputes the score client-side from
  `files[].mutants[]`. **This means the parent ticket's "aggregate stats
  would need recomputing, rebuild the whole Result" concern doesn't
  apply — there's no aggregate stored in the file to recompute.**
  Merging `files` is a complete fix.

## Design decision: merge at the schema/hash level, keyed by `stableId`

**Not** file-level replacement (the parent ticket's sketch), and **not**
reconstructing live `Mutant` objects from old JSON to run back through
`Result`. Both rejected, with reasons:

- Reconstructing `Mutant`s from serialized JSON to feed through
  `build_files_section`/`mutant_to_schema` is lossy (needs live
  `mutated_node`/`original_node` for `safe_unparse`, `result.rb:172-174`)
  and pointless — the prior data is already in the exact target schema.
- **File-level merge would be actively buggy for `--survivors-from`.**
  A survivor rerun's schema contains only the re-verified survivors for
  a file; replacing that file's whole entry would silently drop every
  other (e.g. Killed) mutant in the same file — a "looks complete, is
  subtly wrong" regression, worse than today's honest full-overwrite.
  A scoped subject-pattern run has the identical problem when a file
  contains multiple classes and only one is in scope.

**Correct granularity: per-mutant, keyed by `stableId`** (already
emitted per mutant, `result.rb:150`, same identity `MutantHistoryStore`
uses via `MutantIdentity.stable_id`). Merge rule: remove every prior
mutant whose `stableId` appears in the current run's output; add all
current-run mutants; regroup by file; drop any file left with zero
mutants. This handles subject-scoped runs, `--since` runs, and
`--survivors-from` reruns uniformly with **no special-casing** —
survivor-rerun safety falls out for free because it only ever touches
the `stableId`s it re-verified.

## Full-run vs. scoped-run detection

No existing single signal for "this invocation covers 100% of
configured `includes`" — must be added. The building blocks already
exist in `Runner`:
- Subject-pattern scoping ⇔ `pattern_subjects.any?` (`runner.rb:279-281`,
  branch already exists in `resolve_subjects`, 96-104).
- `--since` scoping ⇔ `@since` set (`filter_changed`, 270-277).
- Survivor rerun ⇔ `survivor_rerun?` (`@survivors_from` non-nil, 297-299).

Add `Runner#full_run? = pattern_subjects.empty? && @since.nil? && !survivor_rerun?`.
Pass it into `Result.new` as `authoritative: full_run?` (mirrors the
existing `partial_rerun:` kwarg) at both construction sites
(`build_result`, 158-172; `dry_run_result`, 81-94 — harmless there,
dry runs write no reports). Reporters branch on `result.authoritative?`.

**Important: do not conflate this with the per-test-coverage plan's
"full run" concept.** That plan's `full_run` (in
`docs/backlog/2026-07-08-per-test-coverage-completeness-check-plan.md`)
is about *test-suite* scope (did the coverage bootstrap run all specs —
currently always true). This ticket's `full_run?` is about *subject/
mutation* scope (did this invocation mutate the whole configured
source set). A scoped `henitai run 'Foo*'` today is full on the first
axis but scoped on the second. Keep the two predicates distinct and
separately named; the only thing genuinely shared between the two
efforts is the `stableId`/`MutantIdentity` keying concept (already
present, no new plumbing needed) and the general principle that both
should sequence together if subject-scoped *coverage bootstrap* is ever
reintroduced (it existed once, in commit `7f1193d`, and was reverted —
see the per-test-coverage plan's verification section for the full
history; additive merge in both places is what would make bringing it
back safe).

## `--survivors-from` interaction

Handled uniformly by `stableId` merge (see above) — no special case.
`authoritative?` is false for survivor reruns, so they take the merge
path; `partialRerun`/`unmatchedSurvivorIds` (current-run values) are
carried through as top-level singletons same as today.

## Top-level singletons in a merged report

`sessionId`, `thresholds`, `gitSha`, `partialRerun`,
`unmatchedSurvivorIds` all take the **current run's** values (freshest
session wins) — there's no aggregate score/count field to merge or
recompute (see citation correction above). This removes the "may
require restructuring `Result`" risk the parent ticket flagged.

## HTML reporter

`Reporter::Html#escaped_report_json` (`reporter.rb:378-383`) embeds
`to_stryker_schema` directly — untreated, it stays scoped-thin even
after JSON is fixed. Recommendation: route both reporters through the
same pure merger, made idempotent (current mutants always overlay by
`stableId` regardless of application order), so `run_all`'s reporter
ordering (`reporter.rb:29-33`) doesn't matter. JSON-only is an
acceptable first cut per the parent ticket, but since the merger is a
shared pure function, doing both is nearly free and avoids a window
where JSON is complete and HTML is thin. Lean toward shipping both
together. Explicitly **do not** merge `write_session_snapshot`
(`reporter.rb:282-289`) or `write_activation_recipes` (291-302) — those
are intentionally per-session artifacts, and the snapshots are also the
recovery path if a merge bug ever ships (see Risk below).

## Implementation sketch

**New: `lib/henitai/canonical_report_merger.rb`** (pure function,
fail-safe on any anomaly):

```ruby
module Henitai
  module CanonicalReportMerger
    def self.merge(current_schema, prior_path)
      current = stringify(current_schema)               # JSON round-trip -> string keys
      return current unless File.exist?(prior_path)

      prior = JSON.parse(File.read(prior_path))
      return current unless prior.is_a?(Hash) && prior["files"].is_a?(Hash)

      current_ids  = mutant_ids(current)                 # stableId set from this run
      merged_files = deep_dup(prior["files"])
      merged_files.each_value { |f| f["mutants"].reject! { |m| current_ids.include?(m["stableId"]) } }

      current["files"].each do |file, entry|
        merged_files[file] ||= entry
        merged_files[file]["source"]  = entry["source"]
        merged_files[file]["mutants"] = merged_files[file]["mutants"] + entry["mutants"]
      end
      merged_files.reject! { |_, f| f["mutants"].empty? }

      merged = current.merge("files" => merged_files)    # current run owns top-level singletons
      safety_check!(merged, current)                     # merged count >= current count; error names the thinned file, else raise
      merged
    rescue StandardError
      stringify(current_schema)                          # never worse than today's overwrite
    end
  end
end
```

**`Reporter::Json`**: `write_canonical` writes `schema` unchanged when
`result.authoritative?`; otherwise writes
`CanonicalReportMerger.merge(schema, canonical_path)`.

**`Reporter::Html`**: same conditional merge before embedding into
`escaped_report_json`.

**`Result`**: add `authoritative:` constructor kwarg + `authoritative?`
reader (mirrors existing `partial_rerun?`).

**`Runner`**: add `full_run?`; pass `authoritative: full_run?` at both
`Result.new` call sites. Add a one-line comment directly on `full_run?`
in the implementation (not just here) flagging that this predicate is
*subject/mutation-scope* only — distinct from the per-test-coverage
plan's *test-suite-scope* `full_run` concept
(`docs/backlog/2026-07-08-per-test-coverage-completeness-check-plan.md`).
Both plans touch `runner.rb`; without an in-code marker, a future
implementer merging both is the most likely place these get conflated.

**Key implementation gotcha:** `Result#to_stryker_schema` emits **symbol**
keys; `JSON.parse` on the prior file yields **string** keys. Merge in
string space — round-trip the current schema through
`JSON.parse(JSON.generate(current_schema))` before merging. Do **not**
pass `symbolize_names: true` when parsing the prior file — that would
also symbolize file-path keys, breaking the merge's file-key equality.

**`deep_dup` is not a stock Ruby method** — there is no ActiveSupport
dependency in this gem (verified: zero hits for `deep_dup`/
`ActiveSupport` repo-wide). Implement it explicitly, e.g.
`Marshal.load(Marshal.dump(prior["files"]))`, or a small recursive
Hash/Array dup. **This is not a cosmetic gap:** the sketch wraps the
entire merge in `rescue StandardError` as a fail-safe, so a
`NoMethodError` from a missing `deep_dup` would **silently fall through
to the current-only fallback on every call** — the merge feature would
ship as a permanent no-op, structurally indistinguishable from today's
overwrite behavior, and no exception would ever surface it. The only
guardrail against this class of bug is a test that asserts the merged
*content* (e.g. "file X's mutants from run A are still present after
run B"), not just "no exception was raised." Treat that assertion as
load-bearing, not incidental, in the test plan below.

## Test plan

- **Scoped merge:** full run A covers files X, Y; scoped run B (only
  Y's subjects) → merged report has both X and Y; X's mutants
  byte-identical to A's; Y updated to B's results.
- **Full replace:** scoped B, then full A → A fully replaces; no stale
  entries survive for a file A no longer produces mutants for.
- **Survivor-rerun correctness (the critical case):** prior file X has
  `{Killed: K1, Survived: S1}`; `--survivors-from` reruns S1 (now
  Killed) → merged X = `{K1 unchanged, S1 → Killed}` — assert K1 is
  present and untouched, total count preserved.
- **`stableId` overlay:** same `stableId` present in both prior and
  current → current wins (status/duration/`fromCache` all updated).
- **Fail-safe paths:** prior file missing, corrupt JSON, or missing
  `"files"` key → returns current-schema-only, no exception (matches
  today's behavior exactly, i.e. never a regression).
- **Idempotency:** merging an already-merged file a second time with
  the same current schema produces the identical result (guards
  JSON/HTML reporter-ordering assumptions).
- **String-key correctness:** merged output re-parses; file-path keys
  are strings; conforms to the Stryker schema shape.
- **Safety invariant:** merged mutant count is never less than the
  current run's mutant count; a violation triggers the fail-safe
  fallback rather than writing a thinner-than-current report.
- **HTML parity (if shipped together):** embedded JSON in the HTML
  report equals the merged canonical JSON on disk.
- **Side-artifacts untouched:** session snapshots and activation
  recipes remain current-run-only after a merge.
- **Zero-scope `--since`:** `--since` with no changed files (empty
  mutant set, `full_run?` false) must merge to the *unchanged* prior
  report, not wipe it — guards against `full_run?`'s `@since.nil?`
  check being satisfied for the wrong reason.

## Sequencing and risk

**Minimal first step:** JSON-only, `stableId`-keyed, fail-safe merger,
gated on `Result#authoritative?`. HTML follows immediately after if the
merger proves solid (it's nearly free once the JSON path works).

**Dominant risk, and why it's the priority ordering below:** a merge
bug that *drops* mutants is worse than today's honest full-overwrite —
the report would look complete while being subtly wrong, which is
harder to notice than "obviously missing everything." Guardrails, most
important first:
1. **Fail-safe fallback on any anomaly** — write current-only, i.e.
   structurally never worse than today.
2. **`stableId` granularity, not file-level** — the single biggest
   correctness lever; it's specifically what makes `--survivors-from`
   safe without special-casing.
3. **`merged ≥ current` count invariant**, hard-failing to the fallback
   rather than silently writing a thinner report.
4. **One-line observability** (`log` merged file/mutant counts) so a
   thinning regression would be visible in normal output, not just in
   a spec.
5. **Existing recoverability**: per-session snapshots
   (`reporter.rb:310-311`, under `sessions/<id>/`) already preserve each
   run's own untouched data, so a bad merge is recoverable even if one
   ships — this is a safety net, not a substitute for guardrails 1-4.

## Critical files for implementation

- `lib/henitai/reporter.rb` (`Json#write_canonical` 277-280, `Html#report` 343-346, `escaped_report_json` 378-383)
- `lib/henitai/result.rb` (schema construction 109-145; add `authoritative?`)
- `lib/henitai/runner.rb` (add `full_run?`; wire into `build_result` 158-172 and `dry_run_result` 81-94)
- New: `lib/henitai/canonical_report_merger.rb`
