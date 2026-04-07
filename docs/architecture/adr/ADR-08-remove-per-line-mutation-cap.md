# ADR-08: Remove Per-Line Mutation Cap

**Status:** Accepted  
**Date:** 2026-04-07

## Context

`MutantGenerator` enforced a `max_mutants_per_line` limit (default: 1) that kept only
the highest-priority mutation per source line and discarded all others. This was
configurable via `.henitai.yml` under `mutation.max_mutants_per_line`.

A comparative analysis against four established mutation testing frameworks
(mutant, cargo-mutants, infection, stryker-js, stryker-net) found that henitai
is the **only framework with any per-location cap**. All others emit every
mutation each operator produces for every AST node independently.

Consequences of the cap:

- A line with three arithmetic sub-expressions produced exactly one mutant
  regardless of how many operators fired.
- Adding new operators did not increase coverage on lines already mutated.
- The cap interacted poorly with the planned granular operators (unary,
  op-assign, regex, chain-unwrap) whose value depends on producing several
  mutations per expression.
- The per-line priority ordering was an internal implementation detail with no
  external guarantee, making behaviour hard to reason about.

## Decision

Remove `max_mutants_per_line` entirely:

- Delete `prune_mutants_per_line`, `line_key`, `mutant_priority_key`,
  `operator_priority`, and `operator_priority_map` from `MutantGenerator`.
- Remove the `max_mutants_per_line` config key from `Configuration`,
  `ConfigurationValidator`, and the `henitai init` template.
- Sampling (`mutation.sampling`) remains available for users who need to cap
  total mutation volume by ratio rather than by location.

## Consequences

**Positive**

- Mutation count aligns with what operators actually produce, making coverage
  metrics honest.
- New granular operators (see `docs/plans/2026-04-07-missing-operators.md`)
  will contribute proportionally to coverage without being silently discarded.
- Simpler code: ~50 lines removed, no priority-ordering logic to maintain.

**Negative / Mitigated**

- Runs on existing codebases will produce more mutations and therefore take
  longer. Users sensitive to runtime can use `mutation.sampling` to cap total
  volume, or restrict runs to a subject expression.
- `mutation.max_mutants_per_line` in existing `.henitai.yml` files will now
  trigger an "unknown key" warning. Users should remove the key.
