# `equivalence_detector_spec` Uses `send` to Reach Private Operand Predicates

Status: done (2026-08-21)
Date: 2026-08-21
Severity: Low
Source: discovered while seeding budgets for
`spec/infra/private_method_reach_spec.rb`; no ticket existed

## Summary

[`spec/henitai/equivalence_detector_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/equivalence_detector_spec.rb)
reaches 4 private predicates: `zero_operand?`(2), `one_operand?`,
`multiplicative_operator?`.

## Problem

- The predicates decide whether a mutation is AST-provably equivalent, so they
  are load-bearing for `MS`/`MSI` — an equivalent mutant leaves both sides of
  the score. They deserve first-class tests, not `send` reach.
- One example feeds a malformed node (`Node.new(:str, [0])`) to
  `zero_operand?`. That is a defensive branch no public `analyze` input
  reaches, so it cannot simply move to the public path.

## Fix Sketch

Extract `Henitai::EquivalenceDetector::OperandPredicates` into
`lib/henitai/equivalence_detector/operand_predicates.rb`, with
`spec/henitai/equivalence_detector/operand_predicates_spec.rb`.

- A subdirectory keeps the new file out of the top-level 1:1 glob in
  `spec/infra/lib_spec_coverage_spec.rb` while still getting a dedicated spec —
  the same shape as `slot_scheduler/draining.rb`.
- Public `#zero_operand?(node)`, `#one_operand?(node)`,
  `#multiplicative_operator?(symbol)`, plus sibling predicates that travel with
  them for cohesion. Instance methods on a documented class (`Style/Documentation`
  applies), with one memoized instance in the detector.
- The malformed-node case survives as a first-class public test rather than a
  `send`.
- Extend the exempt-subdirectory comment at the top of
  `spec/infra/lib_spec_coverage_spec.rb` to mention `equivalence_detector/`.

## Test Plan

- Capture `bundle exec henitai run 'Henitai::EquivalenceDetector#*'` MS/MSI
  before starting; host plus collaborator must not fall below it.
- Keep the existing `x + 0` / `x * 1` equivalence examples green — the
  conservative guarantees must not loosen.
- Lower this file's budget in `spec/infra/private_method_reach_spec.rb` in the
  same commit.

## Resolution (2026-08-21)

Extracted `Henitai::EquivalenceDetector::OperandPredicates`
(`lib/henitai/equivalence_detector/operand_predicates.rb`) with
`spec/henitai/equivalence_detector/operand_predicates_spec.rb`.

- Public `#additive_operator?`, `#multiplicative_operator?`,
  `#zero_operand?`, `#one_operand?`. `numeric_operand?` moved with them and
  is now private to the collaborator; the detector memoizes one instance and
  delegates.
- The subdirectory keeps the new file outside the top-level 1:1 glob in
  `spec/infra/lib_spec_coverage_spec.rb`, whose exempt-directory comment was
  extended to name `equivalence_detector/`.
- The malformed-node branch -- an operand that is a bare Ruby value rather
  than an AST node -- is now a first-class public test rather than a `send`.
  No parsed source produces that shape, but the detector must not raise on
  synthesized input.
- The two examples deleted from `equivalence_detector_spec.rb` were replaced
  by verdict-level ones through the public `#analyze`: an exponent-by-one
  mutation is equivalent, and non-numeric operands stay pending. The
  predicates keep their own direct coverage in the new spec, so nothing was
  traded away.

Budget removed from the private-reach ratchet in the same commit.
