# `henitai operator list` Never Shows the Hard Set

Status: backlog
Date: 2026-07-27
Severity: Medium
Source: 2026-07-27 release-0.4.0 review

## Summary

`henitai operator list` renders exactly two sections, built from `LIGHT_SET`
and `FULL_SET`. Release 0.4.0 added a third set, so `HashKeyType` and
`EqualityIdentityOperator` are now invisible in the only command that enumerates
operators — including the metadata row the release itself added for
`HashKeyType`. `validate_operator_metadata!` has the same blind spot, so a
future hard-set operator with no metadata prints a "No metadata available"
placeholder instead of failing loudly.

## Problem

- `lib/henitai/cli/operator_command.rb:60-67` — `operator_list_text` builds
  `operator_list_section("Light set", Operator::LIGHT_SET)` and
  `operator_list_section("Full set", Operator::FULL_SET)`; nothing renders
  `Operator::HARD_SET`.
- `lib/henitai/cli/operator_command.rb:89-93` — `validate_operator_metadata!`
  diffs `Operator::FULL_SET` against `OPERATOR_METADATA.keys` only. The
  fallback row (`fallback_operator_metadata`, line 85-87) then silently
  substitutes "No metadata available (n/a)" for anything unlisted.
- `lib/henitai/cli/operator_command.rb:18` — the release *did* add
  `"HashKeyType" => ["Hash key types", '{ a: 1 } -> { "a" => 1 }']`, so the
  metadata exists but is unreachable: dead data today.
- Verified from the constants: `LIGHT_SET + FULL_SET` contains neither
  `HashKeyType` nor `EqualityIdentityOperator`;
  `HARD_SET - FULL_SET == ["EqualityIdentityOperator", "HashKeyType"]`.
- Knock-on effect: the disable-directive error message tells users to run
  `henitai operator list` to find "valid names" (see
  [[2026-07-27-review-disable-directive-rejects-hard-operators]]) — following
  that advice cannot surface the two names in question.
- `EqualityIdentityOperator` regressed: it was listed under "Full set" in 0.3.1
  and is listed nowhere in 0.4.0.

## Fix Plan

1. **Reproduce (red).** In `spec/henitai/cli_spec.rb` (the `operator list`
   examples around lines 1068-1190), assert the output contains a `Hard set`
   section listing `HashKeyType` and `EqualityIdentityOperator` with their
   metadata. Fails today.
2. **Render the hard set.** Add a third
   `operator_list_section("Hard set", ...)`. Pick one convention and apply it to
   all three sections: today the "Full set" section prints the whole
   `FULL_SET` (19 entries), which already re-prints all 7 light operators a
   second time — the sections read as cumulative in the header but as "adds on
   top of" in the docs. Printing `SET - previous_set` for full and hard is the
   smaller, clearer output; either way the three sections must be consistent.
3. **Widen metadata validation (red first).** Add an example asserting that a
   hard-set operator missing from `OPERATOR_METADATA` raises `ArgumentError`;
   then change `validate_operator_metadata!` to diff `Operator::HARD_SET`.
4. **Update the CLI banner.** `lib/henitai/cli.rb:20` still documents
   `--operators SET Operator set: light (default) | full` — fold this into
   [[2026-07-27-review-hard-set-doc-debt]] or fix here, but not twice.
5. Green: `bundle exec rspec spec/henitai/cli_spec.rb`, then the full suite and
   `bundle exec rubocop --parallel`.

## Acceptance

- `henitai operator list` prints every operator in `HARD_SET`, each exactly
  once, with real metadata (no "No metadata available" rows).
- A hard-set operator without metadata fails `validate_operator_metadata!`.
- `spec/henitai/cli_spec.rb` pins the hard-set section.

## Related

- [[2026-07-27-review-disable-directive-rejects-hard-operators]]
- [[2026-07-27-review-operator-registry-invariant-specs]]
- [[2026-07-27-review-hard-set-doc-debt]]
