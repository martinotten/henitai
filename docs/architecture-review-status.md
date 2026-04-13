# Architecture Review Status Matrix

Date: 2026-04-13

This document separates the architecture review findings into a small set of
status labels:
- `stale`: the review statement no longer matches the current codebase
- `confirmed`: the finding still applies
- `todo`: the finding still needs implementation or a documentation decision
- `resolved`: the issue is closed in code or docs
- `docs-only`: the remaining work is documentation alignment, not runtime work
- `obsolete`: the point no longer applies to the current architecture

## Status Matrix

| Point | Status | Evidence | Action |
|---|---|---|---|
| ADR-07 Method Coverage | `stale` | `Coverage.start(lines: true, branches: true, methods: true)` is already present in `spec/spec_helper.rb` and `lib/henitai/minitest_simplecov.rb`. | Remove this from the open-issues list or mark it done in the review. |
| AvailableCpuCount / worker default | `resolved` | The code intentionally keeps the conservative fallback at `1`, and the architecture docs now say so. | None. |
| AridNodeFilter vs UpdateOperator | `resolved` | The asymmetry is now documented in code and in the architecture docs. | None. |
| EquivalenceDetector expansion | `resolved` | The detector now covers obvious logical identities in addition to the existing arithmetic cases. | None. |
| RspecProcessRunner helper access | `resolved` | The runner now calls `Integration::Base` helpers directly; the methods are public instead of being reached through reflection. | None. |
| Inline directives (`henitai:disable`) | `docs-only` | The architecture docs now mark the directive syntax as planned, not implemented. | None unless the feature is implemented later. |
| Execution modes (`dev-fast`, `ci-pr`, `ci-nightly`) | `docs-only` | The architecture docs now describe them as conceptual profiles instead of a first-class API. | None unless a profile layer is added later. |
| `STRYKER_MUTATOR_WORKER` | `obsolete` | The review point no longer applies because the Stryker-specific worker convention was removed. | Drop it from any follow-up list. |
| Gate terminology | `resolved` | The architecture docs now distinguish the cost-reduction gate view from the runner's execution-order view. | None. |

## Implementation Plan

Completed:

- P1: The worker default is explicitly conservative at `1`, and the docs now
  match the runtime behavior.
- P2: The `AridNodeFilter` / `UpdateOperator` asymmetry is documented in code
  and architecture docs.
- P2b: The `EquivalenceDetector` now covers the obvious logical identities
  reported by the review.
- P2c: The `RspecProcessRunner` now uses direct helper calls instead of
  reflection.
- P3: Inline directives are marked as planned, not implemented.
- P4: Execution modes are documented as conceptual profiles, not a first-class
  API.
- P5: Gate terminology now distinguishes the cost-reduction view from the
  runner's execution-order view.
