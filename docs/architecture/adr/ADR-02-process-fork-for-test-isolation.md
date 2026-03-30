# ADR-02: `Process.fork` for Test Isolation

Status: accepted

## Context

Mutation execution must not let one mutant contaminate another. The framework also has to remain compatible with Ruby C extensions and existing test infrastructure.

## Decision

Run each mutant in its own forked child process.

## Consequences

- each mutant gets full memory isolation
- the parent process stays clean even when a child crashes or mutates state
- `Process.fork` benefits from copy-on-write after loading the Ruby runtime once
- the model is not suitable for JRuby or TruffleRuby without adaptation

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
