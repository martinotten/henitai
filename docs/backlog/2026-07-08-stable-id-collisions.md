# Stable-ID Collisions Between Distinct Mutants in One Subject

Status: backlog
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
