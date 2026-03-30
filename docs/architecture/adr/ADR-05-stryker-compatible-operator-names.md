# ADR-05: Stryker-Compatible Operator Names

Status: accepted

## Context

Operator naming needs to work cleanly with dashboards, filters, reports, and Ruby-specific extensions.

## Decision

Use Stryker-style operator names such as `ArithmeticOperator` rather than short research abbreviations such as `AOR`.

## Consequences

- public output stays consistent with the broader Stryker ecosystem
- Ruby-specific operators can follow the same naming pattern
- onboarding is simpler for users who already know Stryker tooling
- literature abbreviations remain useful only as research references

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
