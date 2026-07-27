# Structured Review Findings — 2026-07-27 (release 0.4.0)

Status: backlog (0 of 7 done)
Date: 2026-07-27

Backlog issues from a structured review of the **0.4.0 release** — the hard
operator set (ADR-12): `HashKeyType` split out of `HashLiteral`,
`EqualityIdentityOperator` moved from `full` to `hard`, `HashLiteral` gained
per-pair removal.

Diff under review: `f599162..406a790` (0.3.1 → 0.4.0), 25 files, +369/−59 —
`ce0aae2` (#26, the substantive change) and `406a790` (#27, version bump +
lockfile sync). The review deliberately extended past the diff into every
consumer of the operator-set constants, which is where both regressions live.

This round follows [[2026-06-23-review-index]] (all items resolved).

## Issues by priority

| Sev | Status | Issue | Theme |
|-----|--------|-------|-------|
| High | backlog | [[2026-07-27-review-disable-directive-rejects-hard-operators]] | Correctness — `# henitai:disable HashKeyType` raises `ConfigurationError`; documented escape hatch dead, `EqualityIdentityOperator` regressed from 0.3.1 |
| Med | backlog | [[2026-07-27-review-operator-list-omits-hard-set]] | CLI — `henitai operator list` renders light+full only, so both hard-set operators are invisible and their metadata is dead data |
| Med | backlog | [[2026-07-27-review-hash-pair-label-ast-leak]] | Correctness/reporting — pair-removal descriptions emit AST s-expressions, incl. multi-line, and duplicate empty labels for variable keys |
| Med | backlog | [[2026-07-27-review-operator-registry-invariant-specs]] | Tests — nothing asserts the five places an operator set must be wired; both regressions above shipped green |
| Med | backlog | [[2026-07-27-review-hard-set-doc-debt]] | Docs — architecture doc, CLI banner, and `Operator` class comment still describe a two-set model |
| Low | backlog | [[2026-07-27-review-hash-key-type-missing-parser-require]] | Hygiene — only operator file using `Parser::AST::Node` without requiring `parser_current`; works by load order |
| Low | backlog | [[2026-07-27-review-retired-mutant-history-rows]] | Persistence — retired mutant identities stay in the trend export forever; no retirement concept |

## Suggested sequencing

1. **Ship the user-visible fix first**: disable-directive whitelist
   (one-line change) together with the `operator list` hard-set section — they
   share a root cause (`FULL_SET` used where the registry was meant) and the
   directive error message points at the broken listing.
2. **Land the registry invariant spec with step 1**, written red first, so it
   demonstrably catches both regressions.
3. **Pair-removal labels** next: self-contained operator change, but it retires
   another batch of stable ids, so sequence it before any history work.
4. **Doc debt** any time; largest single chunk is the architecture doc §8.1
   operator tables. Decide the `.henitai.yml` `light` vs `full` question here.
5. **History retirement** last — it needs a policy decision and a schema
   migration, and it is the only finding with no user-visible symptom today.

## What this release got right

Worth recording, because it narrowed the review: the operator/set split itself is
sound and well-tested. `Operator::SETS` + `for_set` is a clean extension of the
existing model, the nesting invariant is now pinned by a spec, the schema,
validator, `run_options` help text, and RBS signatures were all updated in
lockstep, and ADR-12 states the killability criterion crisply enough to review
against. The two regressions are both "a constant that means *the registry* was
spelled `FULL_SET`" — a single class of mistake, not a design problem.

## Note on validation

**Environment caveat:** this container has Ruby 3.3.6 only, and the gem requires
Ruby >= 4.0, so `bundle install` cannot resolve and `bundle exec rspec` /
`rubocop` / `steep` / `rake smoke:integration:*` **were not run**. Findings were
verified by reading the code plus standalone probes: the `parser`, `unparser`,
and `prism` gems installed outside the bundle, with the real operator and
directive sources loaded against a minimal `Henitai::Operator` stand-in. Every
concrete output quoted in the tickets (error messages, emitted descriptions,
set membership) comes from those probes, not from inference. Each ticket's fix
plan still starts with a red spec inside the real suite — run the suite on a
Ruby 4.0 host before treating any of these as closed.

Checked and **not** filed:

- **`Operator.for_set` silent fallback.** `SETS.fetch(set.to_sym, LIGHT_SET)`
  looks like it would silently downgrade a typo'd set to `light`, but
  `Configuration#initialize` (`lib/henitai/configuration.rb:62-63`) validates the
  *merged* hash — CLI overrides included — so `--operators bogus` is rejected by
  `ConfigurationValidator` before `for_set` ever runs. The default is defensive,
  not reachable. Non-bug.
- **`HashLiteral` double-splat handling.** Verified empirically:
  `{ foo: 1, **rest }` emits one removal mutant (`{ **rest }`), which is *not* a
  duplicate of the empty-hash mutant, and `{ **a, **b }` emits only the
  empty-hash mutant. The `children.size < 2` guard counting `kwsplat` entries is
  correct in both cases. Matches the release's own specs. Non-bug.
- **`HashKeyType` on unusual symbol keys.** `{ :"a b" => 1 }` and
  `{ :"9lives" => 1 }` mutate to `{ "a b" => 1 }` / `{ "9lives" => 1 }`, both of
  which unparse and re-parse cleanly; `dsym` (`{ "a#{x}": 1 }`), string keys, and
  `**` entries are correctly skipped, so no stillborn mutants. Non-bug.
- **Stable-id collisions from duplicate descriptions.** The empty labels in
  [[2026-07-27-review-hash-pair-label-ast-leak]] do not collide as ids:
  `MutantIdentity` also hashes the unparsed mutated node, which differs per
  removed pair. Downgraded from a correctness finding to a reporting one.
- **Verdict-reuse safety after the identity change.** Retired ids simply miss in
  `verdict_for`, so affected mutants re-execute; no stale verdict can be reused.
  Only the trend export keeps the orphans, which is the (Low) finding filed.

## Related

- ADR-12: `docs/architecture/adr/ADR-12-hard-operator-set.md`
- [[2026-06-23-review-index]] — previous round
- [[2026-06-16-review-index]]
