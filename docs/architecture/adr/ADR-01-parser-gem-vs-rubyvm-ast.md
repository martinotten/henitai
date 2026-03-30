# ADR-01: `parser` Gem Instead of `RubyVM::AbstractSyntaxTree`

Status: accepted

## Context

Henitai needs a reliable Ruby AST backend for traversal, mutation point discovery, and source reconstruction. The framework also has to preserve accurate source locations for the Stryker JSON output.

## Decision

Use the `parser` and `unparser` gems as the primary AST and source-reconstruction toolchain.

## Consequences

- AST traversal is based on a mature, RuboCop-compatible parser
- source reconstruction stays stable enough for mutation injection and reporting
- exact line and column positions remain available for report generation
- Ruby 4 syntax support must be verified continuously, and a fork or maintenance strategy may be required if upstream lags

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
