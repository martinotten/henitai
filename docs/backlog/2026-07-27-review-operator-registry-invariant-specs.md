# No Spec Guards the Operator-Set Registry Invariants

Status: backlog
Date: 2026-07-27
Severity: Medium
Source: 2026-07-27 release-0.4.0 review

## Summary

Adding an operator set touches five places that must agree: `Operator::SETS`,
the autoload list in `operators.rb`, the config schema/validator, the CLI
metadata + `operator list` output, and the `henitai:disable` name whitelist.
Release 0.4.0 updated three of them and silently broke the other two — nothing
failed, because no spec asserts the cross-cutting invariants. Every operator's
own unit spec stayed green while `# henitai:disable HashKeyType` started
aborting runs.

## Problem

- `spec/henitai/operator_spec.rb` (the release's new examples) asserts set
  *nesting* and membership only: `FULL_SET ⊂ HARD_SET`, hard-set names present,
  usually-unkillable names absent from `full`. Nothing checks what other
  components do with those names.
- No spec asserts that a hard-set operator name is a valid
  `henitai:disable` name — the gap that let
  [[2026-07-27-review-disable-directive-rejects-hard-operators]] ship.
- No spec asserts that `henitai operator list` covers every registered operator
  — the gap behind [[2026-07-27-review-operator-list-omits-hard-set]]. The
  existing `cli_spec.rb` examples assert fixed output snippets, so a missing
  section does not fail anything.
- `spec/infra/` already holds exactly this class of repo-level invariant
  (`configuration_schema_spec.rb` pins the `light | full | hard` enum,
  `lib_spec_coverage_spec.rb` pins 1:1 spec coverage, `steep_scope_spec.rb` pins
  the type-check scope) — the registry has no equivalent.

Secondary test-quality note in the release's new specs:
`spec/henitai/operators/hash_key_type_spec.rb` — "mutates each symbol key
independently" asserts that two mutants have two identical description strings
(`["replaced symbol key with string key"] * 2`). That passes even if both mutants
mutated the same key; the following example ("changes only one symbol key in each
mutant") is what actually carries the guarantee. Either strengthen the first
example or drop it as redundant.

## Fix Plan

1. **New spec: `spec/infra/operator_registry_spec.rb`.** Drive everything off
   `Henitai::Operator::HARD_SET` (the widest set = the registry) and assert:
   - every name resolves via `Henitai::Operators.const_get` (autoload entry
     exists) and its class responds to `node_types`;
   - every name has an entry in the CLI `OPERATOR_METADATA` and appears in
     `henitai operator list` output;
   - every name is accepted by `MutationSkipDirectives` as a directive operator
     name (i.e. `VALID_OPERATOR_NAMES` covers the registry, not a subset);
   - `SETS` keys match the config-schema enum
     (`assets/schema/henitai.schema.json`) and
     `ConfigurationValidator::VALID_OPERATORS`;
   - sets nest: `LIGHT_SET ⊆ FULL_SET ⊆ HARD_SET`;
   - every operator source file referencing `Parser::AST::Node` also requires
     `parser_current` (see
     [[2026-07-27-review-hash-key-type-missing-parser-require]]).
2. **Write it red first** — with the current code, the directive-whitelist and
   `operator list` examples must fail, proving the spec would have caught this
   release's regressions. Land it together with those two fixes.
3. **Tighten the `HashKeyType` spec** per the note above.
4. Green: `bundle exec rspec spec/infra/operator_registry_spec.rb`, then the
   full suite and `bundle exec rubocop --parallel` (mind `RSpec/` cop config
   used elsewhere in `spec/infra/`, e.g. the `RSpec/DescribeClass` disable
   comment pattern).

## Acceptance

- Adding an operator to any set without wiring metadata, the autoload entry, the
  schema enum, `operator list`, or the directive whitelist fails a spec.
- The new spec fails on the pre-fix code for both 0.4.0 regressions.

## Related

- [[2026-07-27-review-disable-directive-rejects-hard-operators]]
- [[2026-07-27-review-operator-list-omits-hard-set]]
- [[2026-07-27-review-hash-key-type-missing-parser-require]]
- [[2026-06-16-review-test-overmocking-and-gaps]] — precedent for infra-level guards
