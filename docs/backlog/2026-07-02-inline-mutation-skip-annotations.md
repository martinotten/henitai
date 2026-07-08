# Inline Mutation-Skip Annotations

Status: done
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `mutant` and `cargo-mutants`

## Resolution (2026-07-02)

Implemented as `# henitai:disable` (syntax decided shorter than the
`henitai:disable-mutation` proposed below — "henitai" already implies
mutation):

- `lib/henitai/mutation_skip_directives.rb` — new collaborator reading
  comments via `Prism.parse(File.read(path)).comments`, memoized per
  `[path, mtime]`. Line-scoped (trailing comment) and method-scoped
  (standalone comment in the contiguous comment block directly above the
  `def`, resolved via `subject.source_range`) forms.
- `StaticFilter` — `skip_directives:` injected (DI seam like
  `coverage_report_reader:`); `skip_directive_mutant?` sets
  `mutant.status = :ignored` as a sibling of the `ignore_patterns` check,
  short-circuiting equivalence/no-coverage marking.
- Specs: `spec/henitai/mutation_skip_directives_spec.rb` (13 examples) +
  5 new StaticFilter examples; both integration-smoke fixtures annotated
  and the rake verify helper now asserts ≥1 `Ignored` mutant end-to-end.
- Docs: README "Skipping mutations inline", architecture.md §8.2,
  CLAUDE.md.
- Open questions resolved: no operator-scoped form (blanket only, add
  later if too coarse); no stale-annotation detection (future follow-up).

## Summary

Add a source-level marker that excludes a single line, method, or expression
from mutation without touching shared config. Both comparable tools have
this: `mutant` via RSpec metadata (`mutant: false`, `mutant_expression:`),
`cargo-mutants` via `#[mutants::skip]`. Henitai only has `ignore_patterns` —
a global, regex-based config list applied repo-wide.

## Problem

`AridNodeFilter`/`StaticFilter` (`lib/henitai/arid_node_filter.rb`,
`lib/henitai/static_filter.rb`) both consult `config.ignore_patterns`, a flat
list of regexes checked against every candidate node/location repo-wide
(`.henitai.yml`). There is no way to say "skip mutation on this one line" or
"this one test doesn't count as a kill" without either:

- writing a regex broad enough to hit the one call site, and risking it
  matching other unrelated code, or
- editing `.henitai.yml` for a single one-off exclusion that has nothing to
  do with the rest of the project's arid-node policy.

This is a real gap for legitimately-equivalent-but-not-AST-provable code
(outside `EquivalenceDetector`'s conservative `x + 0`/`x * 1` scope) and for
intentionally untested defensive branches that a developer has already
reviewed and accepted.

## Proposed Behavior

A magic comment, checked against the mutant's `location` before it's
included in a run:

```ruby
def risky_calc(x)
  x * 2 # henitai:disable-mutation
end
```

or, for a whole method/block:

```ruby
# henitai:disable-mutation
def legacy_shim(x)
  x - 1
end
```

- Line-scoped form: mutants whose `location[:start_line]` matches a line
  carrying the trailing comment are dropped.
- Method-scoped form: a leading comment immediately above a `def`/`defs`
  drops every mutant whose location falls inside that method's body.
- Dropped mutants should still be counted (as `:ignored`, matching the
  existing `Equivalent`→`Ignored` serialization precedent) rather than
  silently vanishing from the report — a reviewer should be able to see
  what was excluded and why.

## Suggested Interface

Extend `StaticFilter` (not `AridNodeFilter`) with a new check reading
trailing/leading comments from the Prism-parsed source. This has to be
`StaticFilter`, not `AridNodeFilter`: `AridNodeFilter` runs inside
`MutantGenerator`, suppressing AST nodes *before* `Mutant` objects exist —
there is nothing to set `status = :ignored` on at that point. `StaticFilter`
already sets `mutant.status = :ignored` for `ignore_patterns` matches
(`lib/henitai/static_filter.rb`), which is the exact behavior this feature
needs, so the new check is a sibling of that existing logic, not a new seam.
Comment retrieval needs verifying — Prism exposes comments separately from
nodes, so this needs a small collector that maps comment line numbers to
the nearest following/enclosing node's location.

## Non-Goals

- No new global config surface — this is strictly a source-level, per-call-
  site marker.
- Not a replacement for `ignore_patterns` (which stays for repo-wide policy
  like logger/debug calls).
- No attempt to also suppress equivalence-detector output; separate concern.
- Source-side only. `mutant`'s `mutant: false`/`mutant_expression:` also
  lets a *test* opt out of counting as a kill — that's a different
  mechanism (test-side, not source-side) and out of scope here.

## Open Questions

- Exact magic-comment syntax and case-sensitivity (`henitai:disable-mutation`
  vs a shorter `henitai:skip`) — should match the RuboCop-style
  `# rubocop:disable` convention this repo already follows for its own lint
  suppressions, for consistency.
- Should the operator name be specifiable (e.g.
  `henitai:disable-mutation ArithmeticOperator`) to allow narrower
  exclusions, mirroring RuboCop's cop-scoped disables? Start without it —
  add only if the blanket form proves too coarse in practice.
- Should CI warn/fail when a `henitai:disable-mutation` marker has no mutant
  at that location anymore (stale annotation), similar to RuboCop's
  unused-disable detection?

## Implementation Notes

- `lib/henitai/static_filter.rb` is the target seam (see Suggested
  Interface above for why `AridNodeFilter` doesn't work here) — the new
  check belongs beside the existing `ignore_patterns` handling there.
- `docs/architecture/architecture.md` §8.2's arid-node filtering list should
  be updated once this lands, noting the new check lives in `StaticFilter`,
  not the arid-node pre-generation pass.
