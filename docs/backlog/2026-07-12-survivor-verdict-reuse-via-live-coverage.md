# Survivor Verdict Reuse via Live Coverage (Extend `--incremental` Beyond Killed)

Status: implemented 2026-07-12 (Phases 0–4 plus scoped dogfood verification),
PR pending review
Date: 2026-07-12
Severity: Medium
Source: follow-up to [[2026-07-06-incremental-verdict-cache]] (the current
`--incremental` feature, done 2026-07-08). Phase 0 collector fix is a
prerequisite implemented within this ticket; interacts with
[[2026-07-08-per-test-coverage-completeness-check]] and
[[2026-07-08-stable-id-collisions]].
Decision record: `docs/architecture/adr/ADR-11-verdict-reuse-fingerprints-over-git-scoping.md`
— fingerprint-proven verdict reuse chosen as the precision mechanism; git-based
auto-scoping filed separately as [[2026-07-12-auto-since-from-report-head]]
(complementary, composes: git picks the scope, fingerprints prove reuse within
it).

> **Reviewed 2026-07-12 (fable).** The first draft's soundness proof was
> invalid against the actual per-test collector: attribution is *first-toucher*
> only, so the "live covering set" structurally cannot see a new test that
> covers already-covered lines — the exact event this feature must detect. That
> draft's own Phase-5 acceptance scenario would have failed nondeterministically.
> This revision makes the collector fix a blocking prerequisite (Phase 0),
> downgrades the soundness claim to a conditional guarantee with an explicit
> blindness list, fingerprints the intersection set instead of `covered_by`,
> and adds a coarse dependency-file hash. See "Review findings" at the end.

## Summary

`--incremental` reuses prior-run verdicts to skip re-executing mutants whose
context is unchanged, but the first release deliberately reuses **Killed
verdicts only** (`incremental_filter.rb:50-56`). Survivors — the results the
tool exists to surface — always re-execute. On any iterative run where most of
the codebase is untouched, survivors dominate the remaining cost.

This ticket extends verdict reuse to **Survived** (and only Survived — see
Non-Goals) by gating reuse on the **current** per-test coverage map, not just
the recorded covering-test file hashes. This is only sound once per-test
coverage attribution is a complete over-approximation of reachability, which
it is **not** today (Phase 0).

## Problem

### Why Killed-only was safe and Survived-reuse is harder

Reuse correctness turns on **monotonicity**:

- **Killed is monotone.** If test `T` killed mutant `M`, then as long as `M`'s
  subject source and `T`'s file are byte-identical, `T` still kills `M`.
  Other tests changing cannot un-kill it. So Killed reuse needs only "killing
  code + covering test files unchanged" — what `covered_tests_fingerprint`
  already proves.
- **Survived is NOT monotone.** Survived means *no* test killed `M`. A newly
  added or edited test can now kill it. Safe reuse requires proving the
  **complete** set of tests reaching `M` is unchanged — none edited, and
  critically **none added**.

The existing fingerprint hashes only the *recorded* covering-test files: it
detects edits/deletions of last-run tests but says nothing about a **new**
test. That is the gap blocking Survived reuse. It is a *soundness* gap:
reusing a stale Survived verdict does not inflate the score — it **deflates or
preserves it** (the mutant stays in the MS denominator, adds nothing to the
numerator). The real harm is a **false negative in the tool's core loop**:
"add a test to kill a survivor, re-run, watch it flip" would silently keep
reporting the mutant as survived.

### FATAL prerequisite: the collector uses first-toucher attribution

`PerTestCoverageCollector#new_line_numbers` (`per_test_coverage_collector.rb:83-90`)
attributes a source line to a test only when the line's cumulative count was
**zero before that test ran**:

```ruby
next unless count.to_i.positive?
next if previous_counts.fetch(index, 0).to_i.positive?   # line 86
```

`Coverage.peek_result` counts are cumulative, so **only the first test in
suite order to execute a line is recorded as covering it.** The map is "first
touchers of each line", not "all tests reaching the line". This makes the live
covering set a structural **under**-approximation — precisely the unsafe
direction.

Failure scenario (the plan's own Phase-5 test):

1. `Foo#bar` covered by `foo_spec.rb` with weak assertions; mutant M survives.
   Recorded covering set `{foo_spec.rb}`.
2. Dev adds `foo_extra_spec.rb` whose strong assertion kills M.
3. `--incremental` run: new spec mtime invalidates coverage; full suite
   re-runs. `foo_spec.rb` runs first (alphabetical/seed); by the time
   `foo_extra_spec.rb` runs, `foo.rb` lines are already positive → its per-test
   entry contains **no** `foo.rb` lines.
4. Live set = `{foo_spec.rb}` = recorded set. Contents/source unchanged →
   **Survived wrongly reused; the new killing test is silently ignored.**

The "no map ⇒ no reuse" fallback never fires (map exists, non-empty). Under
`--order random`, attribution flaps run-to-run, so reuse becomes order-
dependent. **This must be fixed in the collector before the feature is viable**,
and [[2026-07-08-per-test-coverage-completeness-check]] does **not** fix it —
that ticket checks file-*key* presence, not per-line attribution.

## Proposed Behavior

Under `--incremental`, once Phase 0 lands:

1. **Killed reuse — unchanged.** Source hash + recorded covering-tests
   fingerprint. Monotone; no live-coverage dependency.
2. **Survived reuse — new.** Reusable iff **all** hold:
   - stored latest verdict is `Survived` with a recorded intersection-set
     fingerprint;
   - subject source hash unchanged;
   - **live covering set == recorded covering set** — the set of test file
     paths whose *current* per-test coverage intersects the mutant's *current*
     line range equals the recorded set (membership identical: no new, no
     dropped test);
   - every file in that set byte-identical to recorded content;
   - the run-level **dependency fingerprint** (below) is unchanged.
   If per-test coverage is unavailable/empty, or the integration lacks per-test
   support, Survived reuse is **skipped** (re-execute). No live map, no proof.
3. **Everything else re-executes:** Timeout, CompileError, RuntimeError,
   NoCoverage, Ignored, Equivalent, Pending, unknown/ambiguous ids, legacy
   NULL-hash rows.

Membership compared by **path** (line-drift safe); live set computed against
the mutant's current `location`; `subject_source_hash` catches body edits.

**Recorded set = intersection set, not `covered_by`.** `Mutant#covered_by`
(`execution_engine.rb:74-87`) is the *executed* set: `select_tests` minus
`config.test_excludes`, and `PerTestCoverageSelector` falls back to **all
candidates** when the intersection is empty (`per_test_coverage_selector.rb:19`).
Fingerprinting `covered_by` would (a) make thin-coverage survivors carry the
full candidate list → never match a live intersection set, and (b) permanently
mismatch on any repo using `test_excludes` — **including this repo's dogfood
config** — killing reuse entirely. So persist, at record time, the *same
full-map intersection set* the live check computes, via one shared collaborator.
`test_excludes` handling: an excluded-but-covering test present in the live set
still **blocks** reuse (exclusion is child-process hygiene, not reachability).

**Dependency fingerprint (coarse, mitigates Hole 3).** A single run-level hash
of `spec_helper.rb` + `spec/support/**` + fixtures/factories + `Gemfile.lock` +
`.henitai.yml` + `.rspec`. Any change invalidates *all* survivor reuse for the
run. These files influence test behavior but are excluded from coverage
(`source_file?`, `:105-113`) and are not `_spec.rb` files, so they never appear
in any covering set and are otherwise invisible. Production call-graph blindness
(editing a non-subject production file that changes values reaching M) remains
and is documented, not fixed — same acknowledged limitation as the base ticket.

Reporting: reused survivors flagged `fromCache: true`, status stays `Survived`.
Terminal summary split, e.g. `reused 42 of 300 (39 killed, 3 survived)`.

## Why this is sound (conditional guarantee — not unconditional)

Survived reuse is sound **iff all** of:

- **(a)** the per-test map is a complete over-approximation of reachability
  (every test that could kill M is in M's live set) — requires Phase 0;
- **(b)** no file outside {subject source, covering test files, the dependency-
  fingerprint set} that influences those tests' behavior changed — the
  documented blindness list:
  - other **production** files in the call graph (T drives M through `Baz`;
    editing `Baz` changes values reaching M). Same blindness the Killed path
    has and the base ticket accepted.
  - test **order / seed** for state-leaking survivors (`.rspec` seed is in the
    dependency fingerprint, but intra-run ordering of the selected subset is
    not);
  - ENV, gem upgrades not reflected in `Gemfile.lock`.

Given (a)+(b): membership-equal + content-equal ⇒ the exact set of tests
reaching M is unchanged in identity and content ⇒ no test that could kill M is
new or modified ⇒ survived stays survived.

The dangerous direction is **under**-approximation (a): a missed killing test
⇒ wrong reuse. Over-approximation is harmless (only forces an unnecessary
re-run). Contrast `PerTestCoverageSelector`, which safely over-selects because
there the cost is only time; here the cost is a wrong survivor verdict, so the
fallback must always be "re-execute", never "assume covered".

## Non-Goals

- No reuse of Timeout / CompileError / RuntimeError (environment/timing
  dependent).
- Not making `--incremental` default this release (separate ticket after soak).
- No per-example (below file) coverage granularity.
- No change to `--since` or `--survivors-from` semantics. Automatic `--since`
  derivation from the report's recorded HEAD is a separate ticket
  ([[2026-07-12-auto-since-from-report-head]]).
- No cross-machine cache sharing.
- **Level 3 transitive-closure fingerprinting deferred** (explicit follow-up):
  fingerprint every source file the covering tests *loaded* (the per-test map
  already records this per test) as one combined SHA per survivor — closes the
  production-call-graph blindness documented below for roughly one extra
  column. Do after this ticket soaks; reuses `combined_content_sha`.
- **Blob-OID fast path deferred**: on a clean git tree,
  `git rev-parse HEAD:path` proves file-unchanged without reading content —
  optimization only, semantics identical to the content hash.

## Open Questions

- **Flaky survivors.** A survivor that survived only because a flaky test
  didn't kill it (within `max_flaky_retries`) is reused as survived. Acceptable
  but document (unlike Killed, where retries are benign).
- **`verdict_for` latest-row semantics.** Must return the *most recent* verdict:
  a mutant with an old Killed row and newer Survived row resolves Survived, and
  vice versa. Specify in Phase 1.
- **Executed-only score.** With survivors cached, the survivor list — the core
  output — is partly synthetic. Promote executed-only MS/MSI (deferred in base
  ticket) to at least a first-class reused/executed split in the report, not
  just a terminal line. Leaning in-scope.
- **Bootstrap join point.** Survivor reuse reads the map at Gate 3.5; the
  bootstrap thread is `.value`-joined at `runner.rb:111` before the filter runs,
  so the read is not racy — add a regression spec so a future refactor can't
  let the filter read a mid-write map.

## Implementation Notes

- `lib/henitai/per_test_coverage_collector.rb` — **Phase 0**: attribute a line
  to every test whose execution incremented its count (compare counts, not
  positivity; or clear/restart per test). This is the load-bearing fix.
- `lib/henitai/verdict_fingerprint.rb` — add a live-covering-set helper; factor
  the line-intersection logic shared with `PerTestCoverageSelector#covers_mutant?`
  into a shared collaborator (e.g. `PerTestCoverage#tests_covering(mutant)`),
  reused by the completeness-check ticket too.
- `lib/henitai/incremental_filter.rb` — `reusable?` branches on stored status;
  new `survived_reusable?` needs the live map + dependency fingerprint injected;
  keep the ambiguous-stable-id guard.
- `lib/henitai/mutant_history_store/verdict_cache.rb` — persist the intersection-
  set fingerprint for **survived** rows (currently gated `== "killed"`, `:19`);
  carry forward for `from_cache?` survivors; ensure `--survivors-from`-restored
  `covered_by` (`survivor_rerun_strategy.rb:108`) is not persisted as a fresh
  fingerprint.
- `mutant_history_store.rb` / `sql.rb` — no new columns; existing two nullable
  hash columns now populate for survived rows. Legacy survived rows stay
  NULL = never reusable.
- `runner.rb` — inject reports dir / live per-test map + dependency fingerprint
  into `apply_incremental_filter` (`:121-125`); do not trust bootstrap's
  `per_test_coverage_ready?` skip for unsupported integrations — the filter
  does its own availability check.
- Reporter — split killed/survived reuse counts; add reused/executed score
  breakdown; `fromCache` field already exists.

## Fix Plan (TDD)

**Phase 0 — collector attribution (BLOCKING prerequisite):**

0a. **Red.** `per_test_coverage_collector_spec.rb`: two test files exercising
    the same source line both record that line, in either suite order.
0b. **Green.** Count-delta (or per-test clear) attribution; verify no perf
    regression on the dogfood suite.
0c. Note in [[2026-07-08-per-test-coverage-completeness-check]] that this is
    the attribution fix it does not provide.

**Phase 1 — persist survivor fingerprints (store):**

1. **Red.** `#record` persists source hash + intersection-set fingerprint for
   **survived** mutants; killed unchanged; other statuses NULL.
2. **Red.** `verdict_for(stable_id)` returns the **latest** verdict + hashes;
   Killed-then-Survived history resolves Survived; nil for legacy/unknown.
3. **Green** both; carry-forward spec incl. `--survivors-from`-restored
   `covered_by` not clobbering stored fingerprints. Refactor.

**Phase 2 — live covering set + dependency fingerprint:**

4. **Red.** Shared live-covering-set helper: per-test map + mutant location →
   sorted covering paths; empty map → empty; drift resolves against current
   location. Dependency-fingerprint helper hashes the support-file set.
5. **Green.** Extract shared intersection logic from `PerTestCoverageSelector`.

**Phase 3 — filter (correctness core):**

6. **Red.** `incremental_filter_spec.rb` survivor matrix:
   - Survived, source unchanged, live == recorded, contents + deps unchanged
     → reused (status Survived, `from_cache`).
   - **new test now covers subject** (live ⊋ recorded) → re-run.
   - covering test dropped (live ⊊ recorded) → re-run.
   - covering test content changed → re-run.
   - dependency-fingerprint file changed (e.g. `spec/support/factories.rb`)
     → re-run.
   - subject source changed → re-run.
   - per-test coverage unavailable/empty **or integration unsupported** → re-run.
   - recorded set produced by selector fallback → re-run.
   - mutant's source file absent from every test's coverage while recorded set
     non-empty → re-run.
   - stored Killed → existing killed path (regression guard).
7. **Green.** `survived_reusable?`; inject live map + dependency fingerprint.

**Phase 4 — wiring, CLI, reporting:**

8. **Red.** `runner_spec.rb`: `--incremental` injects live map + deps; without
   the flag, filter never constructed (default path byte-identical). Regression
   spec: filter reads the map only after `bootstrap_thread.value`.
9. **Red.** Reporter: reused survivors emit `fromCache: true`/status Survived;
   summary splits killed/survived; report exposes reused/executed score split.
10. **Green** all; rubocop, steep, full suite.

**Phase 5 — end-to-end (order-adversarial):**

11. Dogfood two-run: edit an *unrelated* method → untouched subject's survivors
    reused (proves `test_excludes` config still achieves reuse). Then add a
    killing spec that **sorts/runs after** the existing covering spec — the
    Phase-0 regression case — and confirm that mutant re-runs and flips to
    Killed while unchanged siblings stay reused. Run twice with different seeds
    if order is randomized.
12. Re-add smoke double-run assertion once [[2026-07-08-smoke-fixtures-never-kill]]
    lands.

## Acceptance

- Opt-in only: without `--incremental`, output byte-identical to today.
- Phase 0 shipped: per-test map attributes every covering test, order-
  independent (spec-proven).
- Survived reused **only** when: source unchanged AND live intersection set ==
  recorded set (membership + content) AND dependency fingerprint unchanged.
- **New or changed covering test invalidates** reuse — proven by an
  order-adversarial spec that adds a killing test after the covering one and
  asserts the mutant flips.
- Per-test coverage unavailable/empty/unsupported ⇒ survivors always re-execute.
- Selector-fallback and `test_excludes`-affected survivors handled correctly
  (recorded as intersection set; excluded-but-covering test blocks reuse).
- Killed reuse and the ambiguous-stable-id guard unchanged.
- Timeout/CompileError/RuntimeError/NoCoverage never reused.
- Reused survivors visible (`fromCache: true`, status Survived), counted in
  MS/MSI, split in the summary, with a reused/executed score breakdown.
- `verdict_for` returns the latest verdict; legacy NULL-hash rows never reusable.
- `--since` and `--survivors-from` paths untouched.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | collector: two-tests-one-line attribution, order-independent (Phase 0) |
| Unit | store: survivor intersection-set persistence + carry-forward; `verdict_for` latest-row matrix |
| Unit | live-covering-set + dependency-fingerprint helpers: membership, empty map, drift |
| Unit | `incremental_filter_spec.rb`: full survivor matrix incl. new-test, dropped-test, deps-changed, no-map, unsupported-integration, fallback-set, killed regression |
| Unit | runner: live map + deps injected under flag; default path never builds filter; read-after-join regression |
| Unit | reporter: `fromCache` survivors, killed/survived split, reused/executed score breakdown |
| E2E | dogfood two-run, order-adversarial: unrelated edit reuses survivors; killing spec added *after* covering spec flips one mutant, siblings stay reused; multi-seed |
| Regression | full dogfood run without flag identical; `--since` and `--survivors-from` untouched |

## Review findings (fable, 2026-07-12)

Verified against source before revising:

- **Hole 1 (FATAL, fixed by Phase 0):** first-toucher attribution
  (`per_test_coverage_collector.rb:86`) makes the live set an under-
  approximation; a new killing test on already-covered lines is invisible.
- **Hole 2:** the completeness-check ticket checks key presence, not line
  attribution — does not close Hole 1. Now stated explicitly.
- **Hole 3 (partially mitigated):** covering *test files* aren't the only
  inputs — support/helpers/factories/config/gems and non-subject production
  code affect survivor outcomes. Coarse dependency fingerprint added for the
  first group; production call-graph blindness documented.
- **Hole 4 (fixed):** fingerprint the intersection set, not `covered_by`
  (selector fallback + `test_excludes` would otherwise kill reuse, notably on
  the dogfood repo).
- **Score-direction error (corrected):** stale Survived reuse *deflates*, not
  inflates, the score; the real harm is a false negative in the add-test loop.
- **Freshness nuance:** added specs *are* watched (invalidate correctly), but
  support/helper files are not — feeds Hole 3's dependency fingerprint.

## Phase 5 verification results (2026-07-12, scoped dogfood)

Single-scope runs on `Henitai::CoverageReportReader*` + `Henitai::TestPrioritizer*`
(sampling temporarily set to 1.0):

- Cold run: 108 killed / 6 survived. Immediate `--incremental` rerun:
  `114 of 114 verdicts reused from history (108 killed, 6 survived)`,
  duration 0.29s (vs 7s executed).
- Order-adversarial flip: a temp spec sorting AFTER
  `coverage_report_reader_spec.rb` (wrapped per-test entry without a
  "duration" key) invalidated coverage, the map was rebuilt, and the rerun
  reported `108 of 114 verdicts reused (108 killed, 0 survived)` with
  `Executed-only MS 33.33% | MSI 33.33%`: all 6 survivors re-executed and the
  two killable `durations_by_test` LogicalOperator survivors flipped to
  Killed (110 killed / 4 survived). Killed reuse was untouched, as designed.
- Observation: the two `TestPrioritizer` survivors also re-ran (instead of
  staying reused) because rebuilding the per-test map under `.rspec` random
  order shifts count-delta attribution of once-executed lines, changing set
  membership. Conservative direction (extra re-run, never wrong reuse); a
  follow-up could pin the bootstrap seed to stabilize attribution.
- After the map rebuild, reuse re-stabilized:
  `114 of 114 verdicts reused from history (110 killed, 4 survived)`, 0.29s.
- Per-test report growth from count-delta attribution (same suite, same
  machine): 100,362 -> 184,224 bytes (~1.84x).
