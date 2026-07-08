# Implementation Plan: Per-Test Coverage Completeness Check

Status: plan — verified by a second Opus subagent, APPROVE WITH CHANGES
Parent ticket: `docs/backlog/2026-07-08-per-test-coverage-completeness-check.md`
Date: 2026-07-08

## Verification verdict (second-pass review, 2026-07-08)

A second Opus subagent independently re-derived every file:line citation
below against current source and re-checked the design's core claims.
**Verdict: APPROVE WITH CHANGES.** The design itself (full-run
provenance manifest + digest, gate `per_test_coverage_ready?`, leave
`coverage_available?`'s weak `any?` alone, reject naive content-set
completeness) holds up. Two floated alternatives were explicitly
rejected: comparing `henitai_per_test.json`/`.resultset.json` mtimes,
and a shared run-id instead of a manifest+digest — neither can
distinguish a full bootstrap from a scoped one, since a scoped writer
produces both files together from the same "generation" just as a full
one does; only a recorded file-set (the manifest) captures what was
actually targeted.

Required changes before implementation:

1. **The P0 root-cause narrative is wrong and must be replaced.** The
   plan blamed "a dev running plain `bundle exec rspec &lt;subset&gt;`."
   Verified false: `henitai/spec_helper.rb` never loads
   `Henitai::CoverageFormatter`, and `.rspec` never requires it —
   `CoverageFormatter` is wired in *only* via
   `Integration::Rspec#suite_command` (`integration.rb:65-72,81`), i.e.
   only when henitai spawns its own subprocess. A plain manual `rspec`
   invocation in this repo cannot write `henitai_per_test.json`.

   The actual cause, found via git archaeology: commit **`7f1193d`**
   ("perf: skip, overlap, and scope the coverage bootstrap (options
   1-3)") introduced **subject-scoped bootstrap** — targeted runs
   derived a scoped spec-file list and passed it into
   `bootstrap_coverage`, so `CoverageFormatter#dump_summary` wrote a
   genuinely thin `henitai_per_test.json`. That code path was removed
   in **`eb4cfd2`** ("Refactor coverage bootstrapper…"), with
   `0ecb91c` ("Retry full coverage bootstrap for targeted runs") in
   between. The thin file that triggered this ticket's repro is almost
   certainly **version drift** — an artifact left by a scoped-bootstrap
   era build (plausible mid-development-on-henitai-itself), read as
   fresh+existing by current full-bootstrap-only code.

   **Consequence:** current-code exposure to this exact trigger is
   lower than the ticket implies — the internal cause is already gone.
   Reframe Part 1 as **hardening against external/stale/cross-version
   writers**, not "the fix for a live internal bug." This does not
   change the fix itself, only how it's motivated. It also means: if
   scoped bootstrap is ever reintroduced (it was a real perf win before
   being reverted), Part 1 (and Part 2's merge-on-write) are exactly
   the pieces that would make it safe to bring back.

2. **Add `henitai_per_test.meta.json` to `REPORT_CLEANUP_PATHS`**
   (`cli.rb:36-43`) — `henitai clean` currently lists
   `henitai_per_test.json` but not the new manifest. Fail-safe if
   missed (stale manifest + absent per-test file → not-available →
   re-bootstrap anyway), but untidy; add a `clean` spec.

3. **Correct a type confusion inherited from the parent ticket's Fix
   Sketch #1.** The per-test JSON's top-level keys are **spec/test
   files** (`record_test(test_file, …)`, keyed by
   `example.metadata[:file_path]`, `coverage_formatter.rb:15-21`), not
   source files — source files are nested per-test under `"coverage"`.
   "The key set is a superset of `source_files`" as literally written
   in the parent ticket compares source files against spec-file keys,
   which is meaningless. This plan's actual design (manifest records
   both `source_files` and `test_files` as separate lists, doesn't
   diff against the per-test JSON's keys at all) sidesteps the
   confusion correctly — just don't let a future reader re-derive the
   broken literal version from the parent ticket's wording.

4. **De-risk the Part 2 digest-ordering coupling, if Part 2 ships.**
   "Compute the digest after the merged write, relying on the child
   having exited before `run_suite` returns" is correct but fragile
   cross-process coupling. Keep the manifest write strictly
   parent-side, after `integration.run_suite` returns `:survived`
   (already the design), and add a spec asserting
   `digest(file_on_disk) == manifest.digest` immediately after a merged
   write. Moot if Part 2 doesn't ship.

5. Dead-code convergence argument (Part 1's core justification):
   **independently reconfirmed correct.** `new_lines`
   (`per_test_coverage_collector.rb:71-81`) only emits an entry for a
   source file with newly-executed lines; a lib file no spec ever
   loads is legitimately and permanently absent from even a correct,
   complete per-test map. A content-set completeness check would
   re-bootstrap on every run for any project with such a file. Caveat:
   henitai's own repo may be near-100% covered so this may not bite
   *here* — but the general case (real downstream projects) requires
   designing around it, which the manifest approach does.

## Executive summary / correction to the parent ticket's Fix Sketch

The parent ticket's Fix Sketch #1 ("verify the per-test JSON's file-key
set is a superset of the resolved `source_files`") is directionally
right but **not safely shippable as written** — it has a convergence
hazard the sketch misses:

1. **`source_files` is not narrowed by the subject pattern.** In
   `Runner#source_files` (`runner.rb:244-252`), `source_files` is *all*
   `lib/**/*.rb` under `config.includes` (minus excludes/`--since`),
   regardless of a subject pattern like
   `'Henitai::Integration::ChildDebugSupport*'` — that pattern only
   narrows `subjects`/mutants. A completeness check against
   `source_files` is effectively "does the map cover the entire
   included source tree," every run.
2. **A naive "every source file must appear as a per-test key" check
   never converges for genuinely-uncovered source files.**
   `PerTestCoverageCollector` records a source file only when a test
   produces *new* covered lines (`record_test` → `new_lines`,
   `per_test_coverage_collector.rb:26-37,71-81`). Any lib file no spec
   ever executes (optional adapters, dead code, etc.) is legitimately
   absent from a correct, full per-test map. Requiring its presence
   forces a full-suite re-bootstrap on **every run** — an everyday
   performance regression, not an edge case.
3. **Comparing against the aggregate `.resultset.json` doesn't fix the
   repro either.** The repro's 172 `:no_coverage` mutants imply the
   aggregate coverage was *also* scoped-thin at that point — `StaticFilter#covered?`
   merges aggregate + per-test (`static_filter.rb:37-55,108-114`), and
   `coverage_available?` (`coverage_bootstrapper.rb:42-47`) only
   requires `covered_sources.any?` (one covered file is enough to pass).
   A completeness check keyed off the aggregate would be blind to
   exactly the gap that needs catching.

**Conclusion:** the robust primary fix is a **full-run provenance
signal** — a small manifest/fingerprint written after a successful
full-suite bootstrap — not content-set inspection of the per-test map.
This sidesteps the dead-code convergence hazard by asking "was this
file produced by our own successful full bootstrap?" instead of "does
its content cover set X?"

**Open assumption (needs P0 confirmation below):** the thin file that
triggered the repro likely came from a non-henitai writer. Henitai's
own bootstrap always runs the full spec suite (`test_files` is `nil`
at the only call site, `runner.rb:196-197`, resolving to
`integration.test_files` = all specs). No henitai code path was found
that writes a thin per-test map on its own.

## P0 — investigation task (do first or in parallel)

Confirm every writer of `henitai_per_test.json`:

- Only two callers construct `PerTestCoverageCollector`:
  `CoverageFormatter#initialize` (`coverage_formatter.rb:12`) and
  `MinitestCoverageReporter#initialize` (`minitest_coverage_reporter.rb:16`).
  Both call `write_report` from their end-of-suite hook.
- **Timeout/interrupt behavior (verified structurally):**
  `RspecProcessRunner#run_suite` (`rspec_process_runner.rb:69-81`) →
  `wait_with_timeout` → `handle_timeout` → `cleanup_process_group` sends
  `SIGTERM` then `SIGKILL` (`integration/base.rb:75-92,100-108`). RSpec
  only traps `INT` (`trap_interrupt`, `integration.rb:85`), so a
  `SIGTERM`/`SIGKILL` kills the child before `dump_summary` runs — **a
  timed-out bootstrap does not write a partial per-test file.**
- On suite *failure* (not timeout), `dump_summary` does run (full
  write) and the bootstrapper then raises `CoverageError`
  (`coverage_bootstrapper.rb:88-91`) — but since the manifest (below)
  is only written on `:survived`, a failed run's file is never trusted
  by the next run anyway.
- Check whether henitai's own dev/CI spec suite leaves a real
  `coverage/henitai_per_test.json` behind from a scoped `rspec`
  invocation with `-r henitai/rspec_coverage_formatter` — this is the
  likely source of the repro and, independent of this fix, is worth a
  documented developer-workflow footgun.

Deliverable: confirm "thin files only come from non-bootstrap writers"
(validates the manifest approach below) vs. "there's a real henitai
path producing partial data" (would raise priority of Part 2).

## Part 1 — Detection (primary fix; ship alone first)

### Design: full-run provenance manifest

`CoverageBootstrapper` writes a small sidecar after every *successful*
full-suite bootstrap; `per_test_coverage_ready?` is gated on it instead
of (or in addition to) mtime/existence.

New artifact: `<reports_dir>/henitai_per_test.meta.json`:

```json
{
  "schema": 1,
  "generated_at": "2026-07-08T12:00:00Z",
  "full_run": true,
  "test_files": ["<expanded spec paths run>"],
  "source_files": ["<expanded source paths targeted>"],
  "per_test_digest": "<sha256 of henitai_per_test.json bytes>"
}
```

**Write side** — `CoverageBootstrapper#bootstrap_coverage`
(`coverage_bootstrapper.rb:83-94`): after `result == :survived` and
before returning, write the manifest capturing `test_files`,
`source_files`, and the sha256 of the just-written
`henitai_per_test.json`. `bootstrap_coverage` doesn't currently receive
`source_files` — thread it through from `ensure!`.

**Read side** — replace `per_test_coverage_ready?`
(`coverage_bootstrapper.rb:149-154`):

```
per_test_coverage_ready? =
  supported? AND
  per_test_coverage_fresh?      (unchanged, mtime gate) AND
  per_test_coverage_available?  (unchanged, exists) AND
  per_test_coverage_authoritative?(source_files, test_files, config)
```

`per_test_coverage_authoritative?`:
- false unless the manifest exists;
- false unless `manifest["per_test_digest"] == sha256(current file)` —
  catches any non-bootstrap overwrite (dev rspec, interrupted process,
  the reported bug);
- false unless the manifest's `source_files`/`test_files` are supersets
  of the current run's (normalized via `File.expand_path` on both
  sides — the manifest is our own artifact, so we control both write
  and read normalization; this avoids the realpath-vs-expand-path
  mismatch between `CoverageBootstrapper#source_file_paths`
  (`coverage_bootstrapper.rb:61-63`, uses `expand_path`) and
  `CoverageReportReader`/`StaticFilter#normalize_path`
  (`coverage_report_reader.rb:77-88`, `static_filter.rb:177-188`, use
  `realpath`)).

**Why this converges without a perf regression:** in steady state
henitai is the sole writer; after one successful full bootstrap the
digest matches and supersets hold, so every later run takes the fast
path. Dead/uncovered source files never enter the check — the manifest
records what was *targeted*, not what was *covered*. Re-bootstrap fires
only when: no manifest exists (first run, or after `henitai clean`),
the per-test file was overwritten by something else (the reported bug),
or watched files changed (already true today).

### New collaborator

`lib/henitai/per_test_coverage_manifest.rb` — `PerTestCoverageManifest`,
mirroring the domain-adjacency of `CoverageReportReader`/`StaticFilter`
(both already own this JSON's shape):
- `write(per_test_path:, source_files:, test_files:, full_run: true)`
- `authoritative_for?(per_test_path:, source_files:, test_files:)` —
  fail-safe: any parse/IO error returns false (→ re-bootstrap).

Register via `autoload` in `lib/henitai.rb` next to the other coverage
classes (`henitai.rb:52-54`). `CoverageBootstrapper` gets a private
`per_test_manifest(config)` memo, called from `bootstrap_coverage`
(write) and `per_test_coverage_ready?` (read).

## Part 2 — Merge-on-write (secondary; not required to fix the reported bug)

Mirrors `MutantHistoryStore#upsert_mutant`
(`mutant_history_store.rb:104-109,130-148`): genuine read-merge-write,
keyed by top-level spec-file key.

`PerTestCoverageCollector#write_report` (`per_test_coverage_collector.rb:39-44`)
changes from unconditional `File.write` to: read existing file if
present → for each test-file key in this run's `serializable_report`,
replace that key's entry wholesale (this run has the complete,
authoritative delta for specs it ran) → leave other keys untouched →
write merged document.

**Pruning renamed/deleted specs:** prune any key whose spec file no
longer exists on disk — this rule is safe regardless of run scope and
needs no full-run flag. Do *not* prune keys for specs that exist on
disk but weren't run in this invocation (that would reintroduce the
scoped-thinning bug in reverse).

**Interaction with Part 1:** the manifest's digest must be computed
*after* the merged write, so the next run's digest check still holds.
Confirmed timing works: the child fully exits (including its merged
write) before `run_suite` returns to the parent
(`rspec_process_runner.rb:74-75`).

**Concurrency caveat:** read-merge-write is not atomic, but there is a
single writer per bootstrap today (one child suite process) — same
single-writer assumption `watched_files_fresh?` already documents
(`coverage_bootstrapper.rb:163-164`). Don't extend merge-on-write to
parallel mutant runs (they don't write this file). If concurrent suite
writers appear later, add write-to-temp + atomic rename then.

## Part 3 — Failure-mode safety (falls out of the design)

- **Timeout:** no partial write (verified above). No action needed.
- **Suite failure:** `dump_summary` runs, then `CoverageError` raises.
  Manifest is written only on `:survived`
  (`coverage_bootstrapper.rb:89`), so a failed run's file has no
  matching manifest → next run re-bootstraps. Correct behavior, free.
- **External/dev overwrite:** digest mismatch → re-bootstrap. Correct.
- Leave `coverage_available?`'s weak `any?` (`coverage_bootstrapper.rb:46`)
  as-is — it's a last-resort guard that raises `CoverageError`;
  strengthening it to "all source_files" reintroduces the dead-code
  hazard and raises instead of re-bootstrapping. Readiness (Part 1),
  not availability, is the correct gate for this bug.

## Files changed

**New:**
- `lib/henitai/per_test_coverage_manifest.rb` (~40-60 lines)

**Edited:**
- `lib/henitai/coverage_bootstrapper.rb` — thread `source_files` into
  `bootstrap_coverage`; write manifest on `:survived`; replace
  `per_test_coverage_ready?` to add the authoritative check; add
  `per_test_coverage_authoritative?` + `per_test_manifest(config)`.
- `lib/henitai.rb` — autoload the new class.
- (Part 2 only) `lib/henitai/per_test_coverage_collector.rb` —
  read-merge-write + on-disk-existence pruning in `write_report`.
  Shared automatically by both RSpec and Minitest paths
  (`coverage_formatter.rb:24`, `minitest_coverage_reporter.rb:29`).

## Test plan

`spec/henitai/coverage_bootstrapper_spec.rb` (extend):
- Per-test file fresh + existing, **no manifest** → bootstrap triggers
  (the reported bug).
- Manifest present but digest mismatches current file (simulated
  external overwrite) → bootstrap triggers.
- Manifest present, digest matches, source/test files ⊆ manifest's, all
  fresh → bootstrap **skipped** (fast-path regression guard).
- Manifest's `source_files` missing a currently-resolved file →
  bootstrap triggers.
- **Dead-code convergence guard:** a full run that legitimately omits
  an uncovered lib file from the per-test *map* still yields the fast
  path next time (manifest lists it under `source_files` regardless;
  digest matches) — explicitly asserts we do NOT re-bootstrap just
  because some file has zero per-test coverage entries.
- Non-`:survived` result → `CoverageError` raised AND no manifest
  written.

New `spec/henitai/per_test_coverage_manifest_spec.rb`:
- `write` then `authoritative_for?` round-trips true.
- Corrupt/absent/parse-error manifest → false (fail-safe).
- Changing the per-test file after `write` flips digest match to false.
- Superset semantics: equal → true, missing → false, extra-in-manifest
  → true.

(Part 2 only) `spec/henitai/per_test_coverage_collector_spec.rb`:
- Scope A written, then scope B written → merged JSON has both.
- Re-running scope A replaces A's entry (no stale accumulation).
- Key whose spec file no longer exists on disk is pruned on next write;
  a key whose spec still exists but wasn't run is kept.
- Empty `@coverage_by_test` still early-returns without clobbering an
  existing file (verify the current `return if @coverage_by_test.empty?`
  guard, `per_test_coverage_collector.rb:40`, still holds under merge).

## Sequencing & risk

1. P0 investigation (cheap, de-risks everything below).
2. **Part 1 alone** fixes the reported symptom and is low blast radius
   (one new class, two method changes, no change to the hot per-mutant
   execution path).
3. **Part 2** only if P0 shows partial/scoped per-test writes are a
   real recurring workflow, or to enable future scoped bootstraps.

**Main risk (perf regression) and its guard:** the manifest approach
is specifically chosen so the fast path holds in steady state; the
"fast-path preserved" and "dead-code convergence" specs above are the
required guardrails before merge — they're what stop this fix from
turning into "re-bootstrap on every single run."

**Residual risk:** if P0 finds a legitimate henitai path writing a
partial per-test file *with* a manifest, digest-match alone won't catch
it — the source/test-file superset check must do the work, which
requires any future scoped-bootstrap code path to honestly record
`full_run: false` and its narrow `test_files` rather than claiming full
coverage.

## Critical files for implementation

- `lib/henitai/coverage_bootstrapper.rb`
- `lib/henitai/per_test_coverage_collector.rb`
- `lib/henitai/coverage_report_reader.rb`
- `lib/henitai/integration/rspec_process_runner.rb` (+ `integration/base.rb` for timeout semantics)
- `spec/henitai/coverage_bootstrapper_spec.rb`
