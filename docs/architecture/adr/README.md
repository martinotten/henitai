# Architecture Decisions

This directory contains one ADR per accepted architecture decision.

## Decisions

- [ADR-01: `parser` gem instead of `RubyVM::AbstractSyntaxTree`](ADR-01-parser-gem-vs-rubyvm-ast.md)
- [ADR-02: `Process.fork` for test isolation](ADR-02-process-fork-for-test-isolation.md)
- [ADR-03: Stryker JSON schema as the native output format](ADR-03-stryker-json-native-output.md)
- [ADR-04: `define_method` for mutant injection](ADR-04-define_method-for-mutant-injection.md)
- [ADR-05: Stryker-compatible operator names](ADR-05-stryker-compatible-operator-names.md)

## Maintenance Rule

Each decision should live in its own file. Update the relevant ADR first, then reflect any architecture-level consequences in [../architecture.md](../architecture.md) and [../../plan/implementation_plan.md](../../plan/implementation_plan.md).
