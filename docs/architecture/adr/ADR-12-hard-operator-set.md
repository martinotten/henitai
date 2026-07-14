# ADR-12: Hard Operator Set for Usually-Unkillable Mutations

**Status:** Accepted
**Date:** 2026-07-14

## Context

`HashLiteral` emitted a symbol-key -> string-key mutation
(`{ a: 1 }` -> `{ "a" => 1 }`). In plain Ruby the two hashes are genuinely
different — symbol/string key confusion is a real defect class — but a large
share of real-world call sites pass hash literals into framework APIs that
normalize key types (ActiveRecord `order`/`where`, strong parameters,
`HashWithIndifferentAccess`). At those sites the mutant is semantically
equivalent, no test can ever kill it, and it surfaces as guaranteed survivor
noise. A static tool cannot see framework normalization, so the mutation is
sound in general and unkillable in practice.

ADR-10 solved the same shape of problem for `==`/`eql?`/`equal?`: the
hardest-to-kill pairing was split into its own operator
(`EqualityIdentityOperator`) and moved out of the default expectations.
But it landed in the *full* set, which still mixes "all reasonable
mutations" with "mutations that mostly produce noise".

## Decision

Introduce a third operator set and re-sort by expected killability:

- `light` ⊂ `full` ⊂ `hard` (strict supersets).
- **full** now means "usually killable": every mutation whose survival is a
  meaningful signal about test quality.
- **hard** adds the usually-unkillable operators on top: currently
  `EqualityIdentityOperator` (moved out of full) and the new `HashKeyType`.
- `HashLiteral` is split: it keeps the empty-hash replacement and gains
  per-pair removal (`{ a: 1, b: 2 }` -> `{ b: 2 }`, skipped for single-pair
  hashes where it would duplicate the empty-hash mutant, and for double-splat
  entries); the symbol-key -> string-key mutation moves to `HashKeyType` in
  the hard set.
- Configuration/CLI accept `light | full | hard` (`mutation.operators`,
  `--operators`); schema and validator updated.

## Consequences

- `full` users get less survivor noise; existing `full` runs emit fewer
  mutants (EqualityIdentity moved out) — a behavior change flagged in the
  changelog, not a bug.
- Per-pair removal strengthens `HashLiteral` in the killable direction:
  "does each individual option matter to any test?" — aligned with ADR-08
  (emit granular mutations, no silent caps).
- `hard` is the explicit opt-in for hunting the last survivors; site-level
  `# henitai:disable HashKeyType` remains available where frameworks
  normalize keys.
- Precedent for future operators: killability decides the set, not
  mutation-family aesthetics.

## Related Documents

- [ADR-08: Remove per-line mutation cap](ADR-08-remove-per-line-mutation-cap.md)
- [ADR-10: Split equality operator](ADR-10-split-equality-identity-mutations.md)
- [Architecture overview](../architecture.md)
