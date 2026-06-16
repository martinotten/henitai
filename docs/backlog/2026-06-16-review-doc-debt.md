# Reconcile README Claims and Consolidate Documentation Debt

Status: backlog
Date: 2026-06-16
Severity: Medium
Source: 2026-06-16 structured review

## Summary

The README under-documents the Full operator set, and the docs tree has grown
overlapping/duplicated planning directories plus committed `.original.md`
backups. Readers cannot tell which docs are canonical.

## Problem

- `README.md:139-147` documents the Full operator set incompletely. Code
  (`lib/henitai/operator.rb` `FULL_SET`, lines 33-46) includes
  `MethodChainUnwrap`, `RegexMutator`, `UnaryOperator`, `UpdateOperator` — the
  README omits these four.
- README marks "Stryker Dashboard integration (untested)" (line 148) while the
  reporter implements an active dashboard POST (`reporter.rb` ~375-379).
  Wording understates a working feature.
- Overlapping doc trees: `docs/plan/` vs `docs/plans/`; `docs/architecture/`
  vs the `architecture-review-*.md` files. `docs/plan/architecture.md` is a
  one-line redirect to the canonical `docs/architecture/architecture.md`.
- Many `*.original.md` backups are committed alongside their compressed
  versions, doubling the file count.

## Fix Plan

1. **README operators.** Add the four missing operators to the Full-set list;
   cross-check each name against `FULL_SET` so the list is generated-accurate.
   Consider a test that asserts README operator names match `FULL_SET` to
   prevent future drift.
2. **Dashboard wording.** Either verify the dashboard POST end-to-end and drop
   "(untested)", or keep the caveat but link to the dashboard-verification
   ticket. Don't leave a working feature labelled untested with no context.
3. **Collapse plan trees.** Pick `docs/plans/` as canonical. Move `docs/plan/`
   content in or archive it under `docs/backlog/done/` (existing convention).
   Remove the stale redirect file.
4. **Backups.** Decide policy on `*.original.md`: either gitignore them (they
   are caveman-compress artifacts) or keep one canonical form. Stop committing
   both versions.
5. Update any cross-references broken by the moves.

## Acceptance

- README Full-set list matches `operator.rb` `FULL_SET` exactly.
- Single canonical planning directory; no dead redirect docs.
- `.original.md` policy decided and applied.

## Related

- [[2026-06-16-review-gemspec-stale-uri]]
- [[2026-06-16-review-repo-hygiene]]
