# Retired Mutant Identities Linger in the History Export Forever

Status: backlog
Date: 2026-07-27
Severity: Low
Source: 2026-07-27 release-0.4.0 review

## Summary

Release 0.4.0 retired a whole family of mutant identities: the `HashLiteral`
symbol-key mutants no longer exist (the operator's descriptions changed and the
mutation moved to `HashKeyType`). Because `MutantIdentity.stable_id` hashes the
description, those rows in `reports/mutation-history.sqlite3` can never match a
mutant again — yet `trend_report` exports every row unconditionally, so the
retired mutants keep appearing in `mutation-history.json` with a frozen
`lastSeenVersion` and a `daysAlive` counter that no longer means anything.

## Problem

- `lib/henitai/mutant_identity.rb:27-36` — `legacy_identity_components` includes
  `mutant.description`, so any description change mints a new id.
- `lib/henitai/mutant_history_store.rb:203-216` — `load_mutants` runs
  `SELECT * FROM mutants ORDER BY first_seen_at, mutant_id` with no filter on
  `last_seen_version`/`last_seen_at`; there is no pruning or retirement concept
  anywhere in the store.
- Consequence for latent-mutant tracking: the trend export mixes live mutants
  with mutants that cannot be produced by the current operator set. A reader (or
  a dashboard consuming the trend JSON) sees survivors that no longer exist.
- Verdict reuse itself degrades correctly — `verdict_for` is a keyed lookup, so an
  orphan row is simply never found and the mutant re-executes once. No wrong
  verdict is reused. This is a reporting/storage-hygiene issue, not a correctness
  one.
- Pre-existing gap (any operator rename or description tweak triggers it), but
  0.4.0 is the first release to retire a family of identities wholesale, and
  [[2026-07-27-review-hash-pair-label-ast-leak]] will retire another batch when
  it lands.

## Fix Plan

1. **Decide the policy first** (cheap, and it decides the code): should the
   history store (a) keep retired rows but mark and exclude them from the trend
   export, or (b) prune rows unseen for N runs/versions? Option (a) preserves the
   audit trail and is the smaller change; record the choice in the ticket before
   coding.
2. **Reproduce (red).** In `spec/henitai/mutant_history_store_spec.rb`: record a
   run containing mutant A, then record a later run containing only mutant B, and
   assert `trend_report[:mutants]` no longer lists A as live (per the chosen
   policy — e.g. A is absent, or flagged `retired: true`).
3. **Implement.** For (a): filter `load_mutants` on the latest run's version /
   `last_seen_at`, or add a `retired` projection; keep the raw rows in SQLite.
   Note the schema migration path — `ensure_schema`/`migrate_mutants_table`
   (lines 100-117) is the existing mechanism for additive columns.
4. **Check the reporter.** `lib/henitai/reporter.rb` consumes `trend_report` for
   the history export; confirm latent-mutant counts and any "days alive" output
   use the live set only.
5. Green: `bundle exec rspec spec/henitai/mutant_history_store_spec.rb`, full
   suite, `bundle exec rubocop --parallel`.

## Acceptance

- The trend export distinguishes live mutants from retired identities.
- Recording a run that no longer contains a previously seen mutant is covered by
  a spec.
- Verdict reuse behavior is unchanged (orphan rows still simply miss).

## Related

- [[2026-07-27-review-hash-pair-label-ast-leak]]
- [[2026-07-08-stable-id-collisions]]
- [[2026-07-06-incremental-verdict-cache]]
- ADR-11: `docs/architecture/adr/ADR-11-verdict-reuse-fingerprints-over-git-scoping.md`
