# Architecture Decisions

This directory contains one ADR per accepted architecture decision.

## Decisions

- [ADR-01: Prism translation instead of `RubyVM::AbstractSyntaxTree`](ADR-01-parser-gem-vs-rubyvm-ast.md)
- [ADR-02: `Process.fork` for test isolation](ADR-02-process-fork-for-test-isolation.md)
- [ADR-03: Stryker JSON schema as the native output format](ADR-03-stryker-json-native-output.md)
- [ADR-04: `define_method` for mutant injection](ADR-04-define_method-for-mutant-injection.md)
- [ADR-05: Stryker-compatible operator names](ADR-05-stryker-compatible-operator-names.md)
- [ADR-06: Terminal progress separate from child logs](ADR-06-terminal-progress-separate-from-child-logs.md)
- [ADR-07: Raw Ruby method coverage for static coverage filtering](ADR-07-method-coverage-for-static-filter.md)
- [ADR-08: Remove per-line mutation cap](ADR-08-remove-per-line-mutation-cap.md)
- [ADR-09: Survivor-only reruns with stable mutant identity](ADR-09-survivor-only-reruns-with-stable-mutant-identity.md)
- [ADR-10: Split equality operator into relational and identity mutations](ADR-10-split-equality-identity-mutations.md)
- [ADR-11: Content-fingerprint verdict reuse, not git scoping, as the skip mechanism](ADR-11-verdict-reuse-fingerprints-over-git-scoping.md)
- [ADR-12: Hard operator set for usually-unkillable mutations](ADR-12-hard-operator-set.md)

## Maintenance Rule

Each decision should live in its own file. Update the relevant ADR first, then reflect any architecture-level consequences in [../architecture.md](../architecture.md) and [../../plans/implementation_plan.md](../../plans/implementation_plan.md).
