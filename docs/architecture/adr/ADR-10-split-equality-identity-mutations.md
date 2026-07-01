# ADR-10: Split Equality Operator into Relational and Identity Mutations

**Status:** Accepted
**Date:** 2026-07-01

## Context

`EqualityOperator` bundled all 9 comparison methods (`== != < > <= >= <=> eql? equal?`)
into a single all-pairs mutator, unconditionally part of `Operator::LIGHT_SET`
(`lib/henitai/operator.rb`). Every send using one of these methods generated a
mutant for every other one, by default.

Comparing this against the `mbj/mutant` gem's operator catalog
(`ruby/lib/mutant/mutation/operators.rb`, `ruby/lib/mutant/mutator/node/send/binary.rb`)
surfaced a deliberate precedent: mutant's default (Light) operator set
**excludes `==` and `eql?` as mutation sources**. Its Full set still generates
`==`↔`eql?`/`equal?`, but the default profile does not. The reason is practical,
not theoretical: most Ruby objects don't observably distinguish `==` from
`eql?`/`equal?` at runtime, so ordinary tests can rarely kill that mutation —
it survives as noise rather than signal. Henitai's own `EquivalenceDetector`
(`lib/henitai/equivalence_detector.rb`) independently confirms this same pairing
is the hardest one it has to reason about: it only proves equivalence for the
narrow case where both operands are statically literal (singleton literals for
`==`/`equal?`, a string literal for `==`/`eql?`); any variable-receiver case is
left as an unproven, usually-unkillable survivor in the default profile.

A wider survey of henitai's other operators (arithmetic, logical,
`MethodExpression`, `MethodChainUnwrap`, etc.) found other places with
undetected equivalence risk (non-literal neutral elements, method aliases like
`size`/`length`), but none of them have a matching precedent in mutant — mutant
in fact deliberately keeps method-alias mutations (`size`/`length`/`count`,
`any?`/`all?`/`none?`) in its Full set because the aliases have subtly
different semantics and are considered real signal, not noise. That is a
useful negative precedent: this decision does not generalize to "aliases are
noise," only to the specific `==`/`eql?`/`equal?` pairing that both frameworks
independently flag as unusually hard to kill.

## Decision

Split the operator space along:

- `RELATIONAL = %i[== != < > <= >= <=>]` (7 ops)
- `IDENTITY = %i[eql? equal?]` (2 ops)

`EqualityOperator` (`lib/henitai/operators/equality_operator.rb`) now only
mutates sends whose method is in `RELATIONAL`, and only emits `RELATIONAL`
replacements. It stays in `Operator::LIGHT_SET` unchanged.

`EqualityIdentityOperator` (`lib/henitai/operators/equality_identity_operator.rb`,
new) covers `RELATIONAL + IDENTITY`, but only emits a mutant when **at least
one side (source or replacement) is in `IDENTITY`** — i.e. it skips exactly the
pairs `EqualityOperator` already covers. It is added to `Operator::FULL_SET`
only.

This reconstructs the original coverage exactly when both operators run
together (`full` set): no mutant is lost or duplicated, only redistributed
between the two classes. In the default `light` set, `eql?`/`equal?` are no
longer mutated at all.

We chose a symmetric split (either side in `IDENTITY` moves to the new
operator) rather than mutant's asymmetric one (only `==`/`eql?` excluded as
*sources*, `<`→`eql?` etc. still reachable in its Light set) so that the
default profile is fully identity-mutation-free, not partially so.

Splitting by operator *class* — rather than threading a light/full parameter
into `Operator#mutate` — follows the existing architecture: `Operator.for_set`
(`lib/henitai/operator.rb`) already decides set membership at the class level
via the `LIGHT_SET`/`FULL_SET` name arrays, and every other operator relies on
that model.

### Alternatives considered

- **Thread operator-set context into `Operator#mutate`.** Rejected — breaks
  the class-level `for_set` model every other operator depends on, just for
  one special case.
- **Rely solely on `EquivalenceDetector`.** Rejected — it only proves the
  narrow literal-operand case; the common variable-receiver case remains
  default-mode noise, which is the problem this decision addresses.
- **Drop `eql?`/`equal?` mutations entirely.** Rejected — contradicts the
  project's Full-set philosophy of exhaustive coverage for thorough runs.

## Consequences

- The default (`light`) operator set no longer generates `==`/`eql?`/`equal?`
  cross-mutations; the `full` set is unaffected in aggregate coverage.
- `EqualityOperator`'s `OPERATORS` constant shrank from 9 to 7 members; any
  code or spec relying on its full original set must use
  `EqualityIdentityOperator` instead.
- The Stryker JSON report will show `"operator": "EqualityIdentityOperator"`
  for identity-involving mutants in full-set runs, instead of
  `"EqualityOperator"`. Because `MutantHistoryStore`'s stable id includes the
  operator name (`mutant_identity.rb`), previously tracked `eql?`/`equal?`-involving
  survivors get new stable ids after this change — a one-time, narrowly scoped
  history reset for that mutant subset, not a bug.
- `henitai operator list` and the CLI's `OPERATOR_METADATA` registry
  (`lib/henitai/cli/operator_command.rb`) needed a new entry for
  `EqualityIdentityOperator`; the command raises if any `FULL_SET` member is
  missing metadata, which caught this during implementation.
- Method-alias equivalence risk elsewhere in the operator catalog
  (`MethodExpression`, `MethodChainUnwrap`) is explicitly out of scope for this
  decision — mutant's own choice to keep alias mutations in Full argues against
  applying the same "noise" reasoning there.

## Related Documents

- [Architecture overview](../architecture.md) — §8.1 Mutation Operators, §9 Architecture Decisions
- [mutant gem analysis](../../research/mutant_analysis.md) — §2.2a, §3.7
