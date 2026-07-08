# Stable-ID Collisions Between Distinct Mutants in One Subject

Status: done (2026-07-08)
Date: 2026-07-08
Severity: Medium
Source: discovered while verifying the incremental verdict cache
(`2026-07-06-incremental-verdict-cache.md`) on the dogfood suite

## Summary

`MutantIdentity.stable_id` (`lib/henitai/mutant_identity.rb`, ADR-09) hashes
`[subject expression, operator, description, file, unparse(mutated_node)]` —
deliberately no source coordinates, so identities survive line drift. But
that also means two *different* mutants in the same subject collide whenever
the operator produces the same replacement with the same description, e.g.
two `MethodExpression — replaced method call with nil` mutants on different
call sites in one method (`mutated_node` unparses to `nil` for both).

Observed on `Henitai::TestPrioritizer#sort`: 19 mutants → only 13 distinct
stable ids; a `CompileError` mutant shared its id with a `Killed` one.

## Impact

- `MutantHistoryStore` keys rows by `mutant_id` — colliding mutants
  overwrite each other's history; trend data undercounts (13 rows for 19
  mutants) and `days_alive`/status history interleave two different mutants.
- The incremental verdict cache would have reused a `Killed` verdict for the
  colliding `CompileError` mutant (score drift). Mitigated 2026-07-08:
  `IncrementalFilter` now refuses to reuse any stable id that appears more
  than once in the current run — correct but forfeits reuse for all
  colliding mutants.

## Fix Sketch

Add a collision-breaking component to the identity that is still
line-drift-stable, e.g. the ordinal index of the mutation site within the
subject (nth occurrence of that node type), or the unparsed *original*
sub-expression being replaced. Requires a migration story for
`mutation-history.sqlite3` (old ids won't match new ones — history restarts
per mutant, acceptable if documented) and re-verification of
`--survivors-from` matching, which also consumes stable ids.

## Test Plan

- Unit: two `MethodExpression` mutants on distinct call sites in one method
  get distinct stable ids; identity still unchanged under pure line shifts.
- History store: colliding fixture from above produces two rows.
- Incremental filter: ambiguity guard becomes dead code for the fixed
  identity — keep it as defense-in-depth, with a spec asserting reuse works
  for the previously-colliding case.

## Resolution (2026-07-08)

Added a collision-breaking `site_offset` component to
`MutantIdentity.identity_components`
(`lib/henitai/mutant_identity.rb`): the mutation site's `start_line`/
`start_col`, expressed **relative to the subject's own `source_range.begin`**
rather than as absolute file coordinates. This still disambiguates two
same-signature mutants at distinct call sites within one subject, while
surviving line drift elsewhere in the file (the whole subject shifts by a
constant delta, so the relative offset is unchanged). Falls back to
`start_col` alone when a subject has no resolved `source_range` (defensive;
doesn't happen for real resolved subjects).

This changes every stable id (migration story from the Fix Sketch): old
`mutation-history.sqlite3` rows won't match new ids, so per-mutant history
restarts — accepted, matches the ticket's documented trade-off; no
schema/migration code needed since ids are opaque hash strings, not schema
fields.

Verified: `spec/henitai/mutant_identity_spec.rb` covers same-subject
distinct-call-site disambiguation and continued drift-stability under a
whole-subject line shift; `spec/henitai/mutant_history_store_spec.rb`'s
stable-id assertion now delegates to `MutantIdentity.stable_id` instead of
duplicating the hash formula (was already brittle to this kind of change);
`spec/henitai/incremental_filter_spec.rb` adds a regression proving two
previously-colliding real `Mutant` objects now get distinct ids and reuse
verdicts independently — the `ambiguous_stable_ids` guard in
`IncrementalFilter` is retained as defense-in-depth per the fix sketch.
Full suite green except 3 pre-existing, unrelated infra failures
(`devcontainer_spec`, `pre_commit_hook_spec`) present on `main` HEAD before
this change. `--survivors-from` re-verified: it round-trips ids opaquely
(store/lookup only), unaffected by the formula change.
