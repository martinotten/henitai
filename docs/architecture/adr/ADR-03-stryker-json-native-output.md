# ADR-03: Stryker JSON Schema as the Native Output Format

Status: accepted

## Context

Henitai needs a canonical report format that can feed dashboards, HTML renderers, and future ecosystem tools without bespoke translation layers.

## Decision

Use the Stryker `mutation-testing-report-schema` JSON as the native serialisation format.

## Consequences

- report consumers can reuse the Stryker ecosystem immediately
- terminal and HTML reports can be derived from the same underlying data
- schema compatibility must be tracked when the upstream schema changes
- the JSON format becomes the source of truth for report semantics

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
