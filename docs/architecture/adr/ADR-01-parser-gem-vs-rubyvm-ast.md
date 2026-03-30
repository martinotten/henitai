# ADR-01: Prism Translation Instead of `RubyVM::AbstractSyntaxTree`

Status: accepted

## Context

Henitai needs a reliable Ruby AST backend for traversal, mutation point discovery, and source reconstruction. The framework also has to preserve accurate source locations for the Stryker JSON output, while supporting Ruby 4 syntax.

## Decision

Use Prism as the parsing backend and translate its syntax tree into parser-compatible AST nodes for traversal and source reconstruction. `unparser` remains the source-reconstruction tool.

## Consequences

- AST traversal stays compatible with the existing parser-style mutation code
- source reconstruction stays stable enough for mutation injection and reporting
- exact line and column positions remain available for report generation
- Ruby 4 syntax support follows Prism's release line, reducing the risk that the parser backend blocks adoption

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
