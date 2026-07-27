# Hash Pair-Removal Descriptions Leak AST S-Expressions

Status: backlog
Date: 2026-07-27
Severity: Medium
Source: 2026-07-27 release-0.4.0 review

## Summary

`HashLiteral`'s new per-pair removal builds its description from
`pair.children.first.children.first`, assuming every hash key is a literal node
whose first child is a printable value. That holds for `sym`/`str`/`int` keys
only. For a `send`, `array`, `hash`, or `dsym` key the expression yields `nil`
or an AST node, so the mutant description becomes an empty label or a raw
s-expression dump — **including embedded newlines** for a nested-hash key. The
description is user-facing in the terminal table, the JSON report, and the HTML
report, and it is also hashed into the mutant's stable id.

## Problem

`lib/henitai/operators/hash_literal.rb:58-62`:

```ruby
# Pair keys are always AST nodes (sym/str/…); their first child is the
# literal value used purely as a human-readable label.
def pair_key_label(pair)
  pair.children.first.children.first
end
```

The comment's claim is false for non-literal keys. Measured against real
`Parser::CurrentRuby` ASTs (standalone probe, Ruby 3.3 + `parser`/`unparser`
gems — the suite needs Ruby 4.0, see the index note):

| Source | Emitted description |
|---|---|
| `{ foo: 1, bar: 2 }` | `"removed hash pair foo"` / `"removed hash pair bar"` — correct |
| `{ "a" => 1, "b" => 2 }` | `"removed hash pair a"` / `… b` — correct |
| `{ 1 => :a, 2 => :b }` | `"removed hash pair 1"` / `… 2` — correct |
| `{ foo => 1, bar => 2 }` | `"removed hash pair "` **twice** — variable keys give an empty label; the two mutants are indistinguishable in every report |
| `{ [1] => 2, x: 3 }` | `"removed hash pair (int 1)"` — s-expression leak |
| `{ "a#{x}": 1, y: 2 }` | `"removed hash pair (str \"a\")"` — s-expression leak, and it names only the first fragment of the interpolated key |
| `{ { a: 1 } => 2, x: 3 }` | `"removed hash pair (pair\n  (sym :a)\n  (int 1))"` — **multi-line** description, and it labels the *inner* pair, not the key |

Impact, in order of severity:

- A multi-line description breaks single-line output surfaces: the terminal
  progress/summary table and the survivor list assume one line per mutant.
- The description feeds `MutantIdentity.stable_id`
  (`lib/henitai/mutant_identity.rb:27-36` hashes `mutant.description`), so these
  strings end up in `reports/mutation-history.sqlite3` and in `stableId` values
  in the canonical JSON report.
- Duplicate empty labels make two distinct mutants read identically in reports.
  They do *not* collide as ids — `mutation_signature` (the unparsed mutated
  node) still differs — so this is a reporting defect, not an identity defect.

Not affected: `HashKeyType`, which only touches `sym` keys and correctly skips
`dsym`, `str`, and `kwsplat` entries.

## Fix Plan

1. **Reproduce (red).** In `spec/henitai/operators/hash_literal_spec.rb`, add
   examples for `{ foo => 1, bar => 2 }`, `{ [1] => 2, x: 3 }`, and
   `{ { a: 1 } => 2, x: 3 }` asserting that (a) no description contains a
   newline, (b) descriptions within one hash are unique, and (c) no description
   contains an `s(`/`(`-prefixed s-expression fragment. All three fail today.
2. **Label from literal keys only, fall back to position.** Replace
   `pair_key_label` with something that returns a printable label for
   `sym`/`str`/`int`/`float`/`true`/`false`/`nil` keys and otherwise falls back
   to a positional label — e.g. `"removed hash pair #2"` (1-based index). An
   alternative is `Unparser.unparse(key)`, which is exact but can be long and
   re-introduces multi-line risk for a nested-hash key; prefer the positional
   fallback and keep the operator free of an Unparser dependency.
3. **Assert the invariant once.** Descriptions must be single-line — consider
   asserting `description` has no newline in the shared operator spec support so
   every operator inherits the check (see `spec/henitai/operators/`).
4. **Note the id churn in the commit message.** Changing any description changes
   the stable id, so already-recorded rows for pair-removal mutants become
   orphans and the affected mutants re-execute once under `--incremental`. That
   is acceptable (correct behavior, one-off cost) but should be stated —
   see [[2026-07-27-review-retired-mutant-history-rows]].
5. Green: `bundle exec rspec spec/henitai/operators/hash_literal_spec.rb`, then
   the full suite and `bundle exec rubocop --parallel`.

## Acceptance

- No mutant description contains a newline or an AST s-expression, for any hash
  key shape (`sym`, `str`, `int`, `dsym`, `send`, `array`, `hash`).
- Two pair-removal mutants from the same hash always have distinct descriptions.
- The code comment above the label helper matches what the code actually
  guarantees.

## Related

- ADR-12: `docs/architecture/adr/ADR-12-hard-operator-set.md`
- [[2026-07-27-review-retired-mutant-history-rows]]
- [[2026-07-08-stable-id-collisions]] — prior work on mutant identity
