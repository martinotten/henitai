# ADR-04: `define_method` for Mutant Injection

Status: accepted

## Context

Mutants need to be activated inside the isolated worker process without introducing temporary files or multi-process write contention.

## Decision

Inject mutated behavior through `Module#define_method` inside the forked child process.

## Consequences

- mutation activation avoids disk I/O per mutant
- concurrent file writes are avoided
- the approach remains aligned with the fork-based execution model
- runtime activation is still sensitive to `eval` and Ruby method semantics, so activation failures must be classified separately from surviving mutants

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
