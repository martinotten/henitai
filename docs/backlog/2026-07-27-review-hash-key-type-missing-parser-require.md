# `HashKeyType` Uses `Parser::AST::Node` Without Requiring the Parser

Status: backlog
Date: 2026-07-27
Severity: Low
Source: 2026-07-27 release-0.4.0 review

## Summary

`lib/henitai/operators/hash_key_type.rb` builds `Parser::AST::Node` objects but
is the only one of the 21 operator files that does not
`require_relative "../parser_current"`. It works today purely by load order —
`Operator.for_set(:hard)` constantizes the `FULL_SET` operators first, and
`HashLiteral` pulls the parser in. Loading or exercising `HashKeyType` on its own
raises `NameError`.

## Problem

- `lib/henitai/operators/hash_key_type.rb:40,45-46` reference
  `Parser::AST::Node`; the file has no `require`/`require_relative` at all.
- All 20 sibling operator files start with
  `require_relative "../parser_current"` (which wraps `require "parser/current"`
  in `Henitai::WarningSilencer`) — this file is the lone exception.
- Verified: loading the file in isolation succeeds (the constant is only
  referenced inside method bodies), and `HashKeyType.node_types` works, but
  `defined?(Parser::AST::Node)` is `nil` afterwards — the first `#mutate` call
  would raise `NameError`.
- Masked in practice on both paths that exist today:
  `Operator.for_set` walks `HARD_SET`, which starts with the `FULL_SET` names,
  and `SourceParser` (`lib/henitai/source_parser.rb:3-4`) loads the parser before
  any mutation happens. So this is latent, not a live crash — a hygiene and
  autoload-robustness issue that a lazily-loaded consumer or an isolated unit
  test would expose.

## Fix Plan

1. **Add the missing require.** Insert
   `require_relative "../parser_current"` at the top of
   `lib/henitai/operators/hash_key_type.rb`, matching every sibling.
2. **Guard the convention.** Add an infra-level example (fits naturally into the
   registry spec proposed in
   [[2026-07-27-review-operator-registry-invariant-specs]]): every file in
   `lib/henitai/operators/` that mentions `Parser::AST::Node` must also require
   `parser_current`. Static source check, no loading required.
3. Green: `bundle exec rspec`, `bundle exec rubocop --parallel`.

## Acceptance

- `hash_key_type.rb` requires `parser_current` like its siblings.
- A spec fails if a future operator references `Parser::AST::Node` without the
  require.

## Related

- [[2026-07-27-review-operator-registry-invariant-specs]]
- ADR-12: `docs/architecture/adr/ADR-12-hard-operator-set.md`
