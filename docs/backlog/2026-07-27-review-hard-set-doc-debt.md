# Documentation Still Describes a Two-Set Operator Model

Status: backlog
Date: 2026-07-27
Severity: Medium
Source: 2026-07-27 release-0.4.0 review

## Summary

Release 0.4.0 updated `README.md`, `CHANGELOG.md`, `CLAUDE.md`, and added
ADR-12, but left the architecture doc, the CLI banner, and the `Operator` class
comment describing the pre-0.4.0 two-set model. The architecture doc is the
authoritative design reference (`CLAUDE.md` says so), and it still lists
`EqualityIdentityOperator` as a full-set operator and does not know
`HashKeyType` exists.

## Problem

Stale after the release:

- `docs/architecture/architecture.md:150` — "The canonical operator model uses a
  small light set first and then grows to a Ruby-specific full set", with a
  Phase 1 / Phase 2 table and no hard set.
- `docs/architecture/architecture.md:311` — §8.1 opens "The operator system is
  split into a light set for MVP stability and a full set for broader Ruby
  coverage."
- `docs/architecture/architecture.md:341` — the "Phase 2 full set" table lists
  `EqualityIdentityOperator`, which moved to `hard` in this release; the table
  has no `HashKeyType` row.
- `docs/architecture/architecture.md:331` — the `HashLiteral` row still reads
  "Replace hash literals with empty or reduced variants | `{ a: 1 }` -> `{}`",
  predating per-pair removal.
- `docs/architecture/architecture.md:343` — "it moved out of the default light
  set while the rest of the relational swaps stayed" — as of ADR-12 it also moved
  out of `full`.
- `docs/architecture/architecture.md:605-611` — the decisions table has rows for
  ADR-07/08/10/11 but none for ADR-12.
- `lib/henitai/cli.rb:20` — usage comment still says
  `--operators SET   Operator set: light (default) | full`. The actual
  `OptionParser` help string was updated (`lib/henitai/cli/run_options.rb:24`),
  so the two disagree.
- `lib/henitai/operator.rb:14-18` — the class doc lists operators under
  "Additional operators (full set)" and includes `EqualityIdentityOperator`;
  `HashKeyType` is absent and the hard set is undocumented at the class level.

Adjacent inaccuracies found while checking the above (pre-existing, not caused by
0.4.0 — fold in or split off as preferred):

- `CLAUDE.md` (Operators section) claims "This repo's own `.henitai.yml`
  dogfoods with `operators: full`", but `.henitai.yml` sets
  `mutation.operators: light`. The line was edited in this release and the false
  clause was carried over. History: `.henitai.yml` did say `full` (set in
  `779a6ea`, confirmed done in the 2026-06-23 review round) and was flipped to
  `light` in `0b8c0ee` — a commit about child-output caps and checkpoint
  reporting, i.e. the change looks incidental rather than intended.
- `docs/architecture/architecture.md:697` — "The full Phase 2 operator set
  (`SafeNavigation`, `RangeLiteral`, etc.) is defined in the architecture but has
  not yet been fully implemented." The 2026-06-23 round corrected the same claim
  at another location (see [[2026-06-16-review-doc-debt]]); this instance was
  missed and all operators exist.

## Fix Plan

1. **Architecture doc §8.1.** Rewrite the framing sentence as three sets
   (`light ⊂ full ⊂ hard`) with the killability criterion from ADR-12. Move the
   `EqualityIdentityOperator` row into a new "Hard set" table, add a
   `HashKeyType` row, and update the `HashLiteral` row/example to
   `{ a: 1, b: 2 }` -> `{}` / `{ b: 2 }`.
2. **Architecture doc §150 table and §343 paragraph.** Reflect the third set;
   restate the ADR-10 sentence so it says the pairing now sits in `hard`, citing
   ADR-12 alongside ADR-10.
3. **Decisions table (§605-611).** Add an ADR-12 row in the established
   "decision | alternatives | status | rationale" shape.
4. **Code comments.** Update `lib/henitai/cli.rb:20` to
   `light (default) | full | hard`, and `lib/henitai/operator.rb:14-18` to list
   the hard set separately with `HashKeyType`.
5. **`CLAUDE.md`.** Either correct the dogfood claim to `light` or change
   `.henitai.yml` to `full` — pick the intended state; do not leave them
   disagreeing. (`docs/backlog/2026-06-16-review-lenient-dogfood-config.md`
   records the earlier intent to dogfood with `full`, so the config is the more
   likely thing to be wrong.)
6. **Line 697.** Delete the stale "not yet implemented" sentence.
7. Verify no other doc asserts a two-set model:
   `rg -n "light set|full set|light \| full" docs README.md AGENTS.md lib`.
8. Green: `bundle exec rspec` (docs-only, but `spec/infra/` asserts some doc
   invariants) and `bundle exec rubocop --parallel`.

## Acceptance

- No doc or code comment describes the operator model as two sets.
- The architecture doc's operator tables match `Operator::LIGHT_SET`,
  `FULL_SET`, and `HARD_SET` exactly, `HashKeyType` included.
- ADR-12 appears in the decisions table.
- `CLAUDE.md`'s dogfood claim and `.henitai.yml` agree.

## Related

- ADR-12: `docs/architecture/adr/ADR-12-hard-operator-set.md`
- [[2026-06-16-review-doc-debt]]
- [[2026-06-16-review-lenient-dogfood-config]]
