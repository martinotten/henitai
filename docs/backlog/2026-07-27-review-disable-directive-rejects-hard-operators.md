# `# henitai:disable HashKeyType` Aborts the Run

Status: backlog
Date: 2026-07-27
Severity: High
Source: 2026-07-27 release-0.4.0 review

## Summary

`MutationSkipDirectives` validates directive operator names against
`Operator::FULL_SET`. Release 0.4.0 moved `EqualityIdentityOperator` out of
`FULL_SET` and added `HashKeyType` to `HARD_SET` only, so both names are now
rejected as unknown: a `# henitai:disable HashKeyType` comment raises
`Henitai::ConfigurationError` and aborts the run. That is the exact escape
hatch ADR-12 and the README tell users to reach for, and
`# henitai:disable EqualityIdentityOperator` is a regression from 0.3.1, where
it worked.

## Problem

- `lib/henitai/mutation_skip_directives.rb:28` — `VALID_OPERATOR_NAMES = Operator::FULL_SET`.
- `lib/henitai/mutation_skip_directives.rb:204-215` — `parse_operator_names`
  calls `error(...)` for any name outside that list, which raises
  `Henitai::ConfigurationError` (line 222-224).
- `lib/henitai/operator.rb:53-56` — `HARD_SET = FULL_SET + %w[EqualityIdentityOperator HashKeyType]`,
  i.e. both names exist in the registry but not in `FULL_SET`.
- Documentation promises the opposite:
  - `README.md:281` — "disable per site with `# henitai:disable HashKeyType`"
  - `docs/architecture/adr/ADR-12-hard-operator-set.md` (Consequences) —
    "site-level `# henitai:disable HashKeyType` remains available where
    frameworks normalize keys"
- The error message is self-defeating: it points users to
  `henitai operator list`, which does not print the hard set either (see
  [[2026-07-27-review-operator-list-omits-hard-set]]).

Reproduced against the real code (standalone probe, Ruby 3.3 + `parser`/`prism`
gems, because the suite needs Ruby 4.0 — see the index note):

```text
VALID_OPERATOR_NAMES includes HashKeyType?              false
VALID_OPERATOR_NAMES includes EqualityIdentityOperator? false

{ order: :asc } # henitai:disable HashKeyType
  -> Henitai::ConfigurationError: <file>: unknown operator "HashKeyType" in
     `henitai:disable` directive at line 4 (valid names: `henitai operator list`)

a == b # henitai:disable EqualityIdentityOperator
  -> Henitai::ConfigurationError: <file>: unknown operator
     "EqualityIdentityOperator" in `henitai:disable` directive at line 4 ...

{ a: 1, b: 2 } # henitai:disable HashLiteral        -> skip? = true
{ order: :asc } # henitai:disable                   -> skip? = true (bare form)
```

Only the bare, all-operator form still works, and it is far coarser than what
the docs promise: it suppresses every operator at that site.

## Fix Plan

1. **Reproduce (red).** In `spec/henitai/mutation_skip_directives_spec.rb`, add
   an example that writes a fixture with a trailing
   `# henitai:disable HashKeyType` and expects `skip?` to be `true` for a
   `HashKeyType` mutant (and `false` for a `HashLiteral` mutant on the same
   line). Add the same for `EqualityIdentityOperator`. Both fail today with
   `ConfigurationError`.
2. **Widen the whitelist.** Change
   `lib/henitai/mutation_skip_directives.rb:28` to
   `VALID_OPERATOR_NAMES = Operator::HARD_SET` — the widest set, i.e. the full
   registry. Add a short comment stating the invariant: the whitelist is the
   *registry*, not the configured set, so a site-level opt-out stays valid
   regardless of which set the run uses.
3. **Guard the invariant structurally.** The whitelist must not silently drift
   again when a future operator lands in a new set — covered by
   [[2026-07-27-review-operator-registry-invariant-specs]].
4. **Confirm the negative path still errors.** An unknown CamelCase name
   (`# henitai:disable NopeOperator`) must still raise with file:line; prose
   directives (`-- reason`) must stay unaffected.
5. Green the suite: `bundle exec rspec`, `bundle exec rubocop --parallel`.

## Acceptance

- `# henitai:disable HashKeyType` and
  `# henitai:disable EqualityIdentityOperator` skip only those operators and do
  not raise, in all three scopes (trailing, standalone-above-`def`, and
  `disable-start`/`disable-end` regions).
- The reason-carrying form (`# henitai:disable HashKeyType: framework
  normalizes keys`) works and the reason still reaches the report.
- Unknown operator names still raise `ConfigurationError` with file:line.
- Specs cover a hard-set operator name in at least one directive scope.

## Related

- ADR-12: `docs/architecture/adr/ADR-12-hard-operator-set.md`
- [[2026-07-27-review-operator-list-omits-hard-set]]
- [[2026-07-27-review-operator-registry-invariant-specs]]
- [[2026-07-06-richer-disable-directives]] — introduced the operator-name grammar
