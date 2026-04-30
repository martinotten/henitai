# ADR-09: Survivor-Only Reruns with Stable Mutant Identity

**Status:** Accepted  
**Date:** 2026-04-17

## Context

Henitai now supports rerunning only the mutants that survived a prior run.
The feature needs a stable identity that survives ordinary source edits, plus
clear rules for how a partial rerun should behave in reports, history, and CI.

The existing `MutantHistoryStore` already needed a stable SHA-256 mutant ID for
trend persistence. Reusing that identity for survivor reruns keeps the feature
internally consistent and avoids introducing a second matching scheme.

Several trade-offs were considered:

- A dedicated `rerun-survivors` command would make the partial scope obvious,
  but it would duplicate the existing `run` setup and option parsing.
- Scope validation based on file overlap is only a heuristic, but it catches
  the common mistake of pointing at a report from the wrong project without
  adding a heavier dependency or a new query surface.
- A partial rerun score is not directly comparable to a full-run score, so
  threshold-based exit checks are misleading in that mode.

## Decision

Implement survivor reruns as a `henitai run --survivors-from <path>` option and
use the Stryker-compatible JSON report as the source of truth.

Concretely:

- extract the stable identity calculation into `MutantIdentity`
- expose the value as `Mutant#stable_id`
- write `stableId` into the JSON report as a vendor-extension field
- load surviving `stableId` values from a prior JSON report
- validate the loaded report shallowly by checking `schemaVersion` and file
  overlap with the configured includes
- filter the current mutant set to the matching survivor subset before mutant
  execution
- mark the result as `partialRerun` and carry survivor selection metadata
  through `Result`
- skip the `runs` table insert in `MutantHistoryStore` for partial reruns
- make partial reruns exit `0` without evaluating the configured threshold

## Consequences

- survivor reruns stay aligned with the canonical JSON report format
- developer workflows can iterate on surviving mutants without rerunning the
  entire project
- trend analytics remain focused on full runs, not partial reruns
- the architecture accepts a shallow scope check instead of a perfect project
  identity check; that trade-off is documented and intentional
- CI users must read the report metadata, not the exit code alone, to interpret
  partial reruns correctly

## Related Documents

- [Architecture overview](../architecture.md)
- [Survivor-only rerun plan](../../plan/survivor-only-rerun.md)
