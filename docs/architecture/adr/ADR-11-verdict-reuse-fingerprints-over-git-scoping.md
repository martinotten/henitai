# ADR-11: Content-Fingerprint Verdict Reuse, Not Git Scoping, as the Skip Mechanism

**Status:** Accepted
**Date:** 2026-07-12

## Context

The goal is to never re-execute a mutant whose outcome provably cannot have
changed. A mutant's verdict is a function of five inputs: the subject source,
the mutation itself, the set of tests reaching it, those tests' behavior, and
the environment. Any skip mechanism approximates "all inputs unchanged"; the
approaches differ in granularity and in which input they can actually prove
unchanged.

Two candidate mechanisms were evaluated:

1. **Git-based scoping** — record the run's `HEAD` in the report; on the next
   run auto-apply `--since <recorded HEAD>` when that commit is an ancestor,
   falling back to an older report matching a known commit. Skips whole
   unchanged files.
2. **Content-fingerprint verdict reuse** — per-mutant proof: subject source
   hash plus a fingerprint of the covering tests, extended for survivors with
   the *live* per-test covering set (membership + content) and a coarse
   dependency-file hash.

Key facts driving the decision:

- Verdict-reuse correctness turns on monotonicity. **Killed is monotone**
  (an unchanged killing test still kills), so Killed reuse needs only the
  recorded covering-test fingerprint — shipped 2026-07-08 as `--incremental`.
  **Survived is not monotone**: a *new or edited* test can kill a previous
  survivor, so safe reuse must prove the complete covering set is unchanged
  in both membership and content.
- Git diffing sees source-file changes but proves nothing about the test
  side at mutant granularity. `--since` skips entire unchanged files with no
  validation that the tests reaching them are unchanged: a new spec that
  kills a survivor in an untouched file is silently ignored and the stale
  Survived entry persists through the report merge. That failure is a false
  negative in the tool's core loop ("add a test, watch the survivor flip") —
  the worst failure mode a mutation-testing tool can have. Note the score
  direction: a stale Survived *deflates* MS/MSI; the harm is the hidden kill,
  not an inflated score.
- The data needed for the fingerprint proof already exists: per-test line
  coverage (`henitai_per_test.json`) maps tests to the source lines they
  execute, and `MutantHistoryStore` already persists per-mutant fingerprints
  keyed by `stable_id` (ADR-09). One prerequisite was found during review:
  the collector attributes each line only to its *first toucher*
  (`per_test_coverage_collector.rb:86`), making the map an
  under-approximation of reachability — the unsafe direction. Count-delta
  attribution fixes this and independently fixes a latent false-Survived bug
  in `PerTestCoverageSelector` test selection.
- Full generality ("cannot have a different outcome") is program
  equivalence — undecidable. The practical ceiling is transitive-closure
  fingerprinting (hash every file the covering tests loaded); the hard floor
  is nondeterminism (flaky or order-dependent tests), which no fingerprint
  can capture.

## Decision

Content fingerprints are the mechanism that decides whether a verdict may be
reused; git is never trusted for that proof.

Concretely:

- Extend `--incremental` verdict reuse from Killed-only to Survived, gated on
  the **live** per-test covering set: a Survived verdict is reused only when
  the subject source hash, the covering set membership, every covering test
  file's content, and a run-level dependency fingerprint (spec helpers,
  support files, factories/fixtures, `Gemfile.lock`, `.henitai.yml`, `.rspec`)
  are all unchanged.
- Fix per-test coverage attribution first (count-delta instead of
  first-toucher) so the live covering set is a complete over-approximation of
  reachability — the soundness precondition.
- Fingerprint the **full-map intersection set**, not `Mutant#covered_by`
  (which reflects selector fallback and `test_excludes` and would make reuse
  permanently miss).
- Any doubt — missing map, unsupported integration, ambiguous stable id,
  legacy rows, selector-fallback provenance — resolves to re-execution, never
  reuse.
- Git-based auto-scoping (auto-`--since` from the report's recorded HEAD) is
  accepted as a *separate, complementary* convenience feature: it picks the
  scope cheaply; fingerprints prove reuse within it. It requires its own
  guard (any test-side change disables auto-scoping) precisely because git
  cannot make the per-mutant proof. Filed as its own backlog ticket.
- Timeout/CompileError/RuntimeError verdicts are never reused
  (environment-dependent, not content-determined).

## Consequences

- Iterative runs skip both proven kills and proven survivors; the remaining
  re-execution set approaches "mutants whose actual input closure changed".
- Soundness is a *conditional* guarantee with a documented blindness list:
  non-subject production files in the call graph, test order/seed effects on
  state-leaking tests, ENV/gem-content drift. Transitive-closure
  fingerprinting (a planned follow-up, cheap because the per-test map already
  records loaded files) closes the first item; the rest is the accepted
  floor, escapable via `--force`.
- Survivor counts in a cached run are partly synthetic; reports must keep the
  executed/reused split first-class (`fromCache`, summary breakdown,
  executed-only score view) so cached survivors are never invisible.
- The per-test coverage report grows (shared lines attributed to every
  covering test, not just the first) and survivors execute more tests per
  run — both accepted costs of correctness; the second also *fixes* current
  under-selection.
- Git remains useful in two bounded roles: scope selection (auto-`--since`)
  and, later, blob-OID fast-path equality checks on clean trees — both
  optimizations, neither a source of truth for reuse.

## Related Documents

- [Architecture overview](../architecture.md)
- [Survivor verdict reuse plan](../../backlog/2026-07-12-survivor-verdict-reuse-via-live-coverage.md)
- [Auto-since ticket](../../backlog/2026-07-12-auto-since-from-report-head.md)
- [Base incremental verdict cache](../../backlog/2026-07-06-incremental-verdict-cache.md)
- [ADR-09: Survivor-only reruns with stable mutant identity](ADR-09-survivor-only-reruns-with-stable-mutant-identity.md)
