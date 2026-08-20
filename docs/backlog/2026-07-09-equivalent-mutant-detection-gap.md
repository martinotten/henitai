# Detect Genuinely Equivalent Mutants Beyond AST-Provable Cases

Status: backlog
Date: 2026-07-09
Severity: Low
Source: discovered while raising `Henitai::Integration::Minitest` from
MS 72.83%/MSI 43.05% to MS 100%/MSI 91.87%

## Summary

`EquivalenceDetector` only flags AST-provable cases (`x + 0`, `x * 1`, etc. —
deliberately conservative, per `docs/architecture/architecture.md`). It
misses semantically-equivalent mutants that require value-domain reasoning
rather than syntactic rewriting, e.g. for `status == true ? 0 : 1` where
`status` is always `true`/`false`:

- `status.eql?(true)` / `status.equal?(true)` for `status == true` — `==`,
  `eql?`, and `equal?` all agree on the `true`/`false` singletons.
- `status <=> true ? 0 : 1` for `status == true ? 0 : 1` — `<=>` returns `0`
  (truthy) when `status` is `true` and `nil` (falsy) when `status` is
  `false`, landing on the same ternary branch as `==` either way.

These stayed Survived on `lib/henitai/integration/minitest.rb:72` (now
`lib/henitai/integration/minitest_test_runner.rb`) after every other
survivor/timeout/no-coverage mutant on that file was killed — no test can
distinguish them from the original, because there is no behavioral
difference to observe. Reported today as ordinary Survived mutants, which
is misleading: a reviewer chasing "kill this survivor" wastes effort on
something no test can ever kill.

## Impact

- MS/MSI numbers include unkillable-but-not-equivalent-labeled mutants,
  understating the practical ceiling for a file's mutation score.
- Contributes to the "Equivalence uncertainty ~10-15% of live mutants"
  caveat already surfaced in the summary line — that caveat is currently a
  guess, not a measured/detected quantity.

## Fix Sketch

Investigate whether these cases are detectable without becoming unsound
(false positives are worse than missing true positives here, per the
existing conservative design):

- Value-domain-restricted equality: when the receiver's static type is
  provably `TrueClass`/`FalseClass` (or more generally a finite/closed set
  of singleton values), `==`/`eql?`/`equal?` mutations among each other are
  equivalent. Needs a lightweight type-narrowing pass, not full type
  inference — scope to boolean-literal comparisons first.
- `<=>`-for-`==` in a ternary/boolean context: when the right-hand side of
  `<=>` is a singleton comparable value and the surrounding context only
  tests truthiness, `<=> ? a : b` vs `== ? a : b` may be provably equivalent
  for closed value domains. Riskier — likely not worth generalizing beyond
  the boolean case above.

## Test Plan

- Fixture mirroring `status == true ? 0 : 1` mutated to `.eql?`, `.equal?`,
  `<=>` — `EquivalenceDetector` marks all three as equivalent (Ignored),
  not Survived.
- Regression: existing AST-provable equivalence fixtures (`x + 0`, `x * 1`)
  still pass — new detection must not loosen existing conservative
  guarantees.
- Counter-fixture: `a == b` where `a`/`b` are not statically boolean/finite
  domain — detector must NOT flag `.eql?`/`.equal?`/`<=>` mutants here
  (guards against false positives for objects with custom `==`).

## Deferral Decision (2026-08-21)

Explicitly **out of scope for 0.5.0** and left open, after review during the
0.5.0 backlog triage.

Reasons:

- The ticket is framed as *investigate*, not *implement*. Its own guiding
  constraint — "false positives are worse than missed true positives" — means a
  wrong implementation silently corrupts `MS` for every user, because an
  equivalent mutant is removed from **both** sides of the score
  (`lib/henitai/result.rb:146-152`).
- It needs a lightweight receiver type-narrowing pass, and no such
  infrastructure exists. `EquivalenceDetector` has AST-literal predicates only;
  there is no notion of a value domain anywhere in the pipeline.
- It is not reproducible with this repository's own configuration:
  `.henitai.yml` uses `operators: light`, and the `.eql?` / `.equal?` / `<=>`
  swaps come from `EqualityIdentityOperator`, which lives in the **hard** set.
  Reproducing needs `--operators hard`.

Current detector scope, for whoever picks this up — it has grown past this
ticket's description and already handles four families, not two:
`equivalent_arithmetic_mutation?`, `equivalent_logical_mutation?`,
`equivalent_singleton_equality_mutation?`, `equivalent_string_eql_mutation?`.

Why the three cases in this ticket still slip through:

- The singleton-equality family requires a *literal* receiver
  (`singleton_literal?(original.children[0])`), so `status == true` with `status`
  an `lvar` is excluded by design. The safety comment at
  `equivalence_detector.rb:135-143` gives the reason: `1.0 == 1` versus
  `1.0.equal?(1)`, and custom `#==`.
- `equality_operator?` is `%i[== equal?]` only, so `.eql?` is not on the
  singleton path at all.
- `<=>` appears in no detector predicate, and there is no ternary or
  truthiness-context analysis anywhere in the class.

If revived, scope it to the boolean case only and skip the `<=>`
truthiness-context arm, which the ticket itself calls "likely not worth
generalizing".
