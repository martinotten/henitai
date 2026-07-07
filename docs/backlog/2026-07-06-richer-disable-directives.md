# Richer `# henitai:disable` Directives (Operator Lists, Block Scope, Reasons)

Status: backlog
Date: 2026-07-06
Severity: Low
Source: cross-framework comparison — StrykerJS 9.6
(`// Stryker disable/restore [next-line] <mutatorList|all>[: reason]`),
mutmut 3.6 (`# pragma: no mutate block` / `start` / `end`), Infection 0.34
(`@infection-ignore-all` at class/method/statement scope) — see
`docs/research/cross_framework_comparison.md` §2.7

## Summary

Henitai's `# henitai:disable` (shipped 2026-07-02 via
`MutationSkipDirectives` in `StaticFilter`) supports two scopes: trailing
comment (line) and standalone comment above a `def` (method). All operators
are always disabled together, and no reason can be attached. The field's
directives are richer on three axes henitai lacks: per-operator selection,
block/region scope, and human-readable reasons that surface in the report.

## Problem

- **All-or-nothing operator scope**: disabling one noisy operator on a line
  (say `StringLiteral` on a log-adjacent string) also silences every other
  operator there — the opposite of henitai's own "matches are reported as
  Ignored, not dropped" auditability goal, because legitimate mutants are
  suppressed as collateral. Stryker's `// Stryker disable next-line
  StringLiteral` solves exactly this.
- **No region scope**: a cluster of N lines needs N trailing comments or a
  method-level disable that overshoots. mutmut's `block`/`start`/`end` and
  Stryker's disable…restore pairs cover this.
- **No reasons**: Stryker's `: reason` suffix lands in the HTML report next
  to the Ignored status, making skip decisions reviewable months later.
  Henitai's Ignored mutants carry no justification.

## Proposed Behavior

Extend the directive grammar, backward-compatible (bare `# henitai:disable`
keeps meaning "all operators, current scope"):

```ruby
x = a + b  # henitai:disable ArithmeticOperator
x = a + b  # henitai:disable ArithmeticOperator, StringLiteral: log-format noise

# henitai:disable RegexMutator: timing-sensitive matcher
def parse(line)
  ...
end

# henitai:disable-start ConditionalExpression
...region...
# henitai:disable-end
```

- Operator names are the canonical public API names (`Operators` registry);
  unknown names are a configuration error (fail fast, mirroring
  ConfigurationValidator style), not silently ignored.
- Reason text (after `:`) is stored on the mutant and serialized into the
  Stryker JSON `statusReason` field (schema supports it) so it shows in the
  HTML report.
- Unmatched `disable-start` without `disable-end` is an error (mutmut raises
  `PragmaParseError` for the same case — follow that precedent).
- Ignored-with-reporting semantics unchanged: everything skipped stays
  visible as Ignored.

## Non-Goals

- No user-extensible AST ignore-plugins (Stryker's `@stryker-mutator/api`
  ignorer plugins) — `ignore_patterns` s-expressions already cover the
  programmatic case.
- No RSpec-metadata-based skipping (mutant's `mutant: false`) — henitai
  skips at the source site, not the test site; that's deliberate.

## Open Questions

- Grammar for method-scope + operator list ambiguity: a standalone
  `# henitai:disable Foo` above a `def` — is `Foo` an operator name or
  accidental prose? Requiring exact registry-name match resolves most of it;
  decide whether near-misses warn.
- Should `disable-start`/`disable-end` nest? (Lean: no — reject nesting,
  simplest correct rule; Stryker allows re-disable but its restore semantics
  are a common confusion source.)
- `statusReason` vs. a vendored extension field — verify current
  mutation-testing-report-schema field name before implementation.

## Implementation Notes

- `lib/henitai/mutation_skip_directives.rb` — grammar extension lives here;
  today it recognizes bare `henitai:disable` in trailing/preceding-def
  positions. Parser must tokenize operator list + optional `: reason`.
- `lib/henitai/static_filter.rb` — consumer; per-operator matching means the
  directive check needs the mutant's operator name, which `StaticFilter`
  already has at that point (verify seam).
- `lib/henitai/operators.rb` — registry lookup for name validation.
- Reporter JSON path (`lib/henitai/reporter.rb`) — reason serialization.
- Specs: `mutation_skip_directives_spec.rb` (grammar: operator lists,
  reasons, start/end pairing, unknown-name error, unmatched-end error),
  `static_filter_spec.rb` (per-operator selectivity: one operator Ignored,
  siblings still Pending), smoke-fixture extension (one per-operator
  disable, assert sibling operator's mutant still executes).

## Decisions (resolving the Open Questions)

- **No nesting** of `disable-start`/`disable-end` — a second `start`
  inside an open region is an error, same class as unmatched `end`.
- **Exact registry-name match required**; unknown names are a hard
  configuration error (run aborts, exit 2) — no fuzzy matching, no
  warning-and-continue. A standalone `# henitai:disable Foo` above a `def`
  where `Foo` is not a registered operator is therefore an error, which
  resolves the operator-vs-prose ambiguity by construction.
- **Schema field**: verify the current mutation-testing-report-schema's
  ignore-reason field name (`statusReason`) as implementation step 0; if
  it differs or is absent in the vendored schema version, use a vendored
  extension field beside `stableId` instead.

## Fix Plan (TDD)

0. Verify the schema field name against the vendored report schema
   (step above); record the answer in this ticket.
1. **Red.** `mutation_skip_directives_spec.rb` grammar matrix:
   - bare `# henitai:disable` (trailing + preceding-def) → all operators,
     unchanged semantics (existing examples stay green unmodified)
   - `# henitai:disable ArithmeticOperator` → only that operator
   - comma list `# henitai:disable A, B`
   - reason suffix `: text` captured (with and without operator list)
   - `# henitai:disable-start X` … `# henitai:disable-end` region covers
     all lines between
   - unmatched `disable-end`, unclosed `disable-start`, nested `start` →
     each raises a directive parse error naming file + line
   - unknown operator name → error naming the bad token and the valid
     names source (`henitai operator list`)
2. **Green.** Extend the parser in
   `lib/henitai/mutation_skip_directives.rb`: tokenize optional operator
   list + optional `: reason`; region tracking for start/end pairs.
3. **Red.** `static_filter_spec.rb`: on a line with mutants from two
   operators and a single-operator disable, the named operator's mutant
   becomes Ignored (with the directive's reason attached), the sibling
   stays Pending. Region case: mutants on all lines inside a start/end
   region Ignored, first line after `end` unaffected.
4. **Green.** `StaticFilter` passes the mutant's operator name into the
   directive match (it has the mutant at that point — verify the seam as
   noted above); attach reason to the mutant.
5. **Red.** Reporter spec: Ignored-by-directive mutants serialize the
   reason into the JSON report (field per step 0); mutants ignored by
   other filters (arid nodes) unchanged.
6. **Green**, refactor.
7. **Red.** Error-path CLI spec: a project containing an unknown operator
   name in a directive aborts with exit 2 and a message with file:line.
8. **Green**; extend **both** smoke fixtures (rspec + minitest, mirroring
   how the base feature shipped): one per-operator disable where the
   sibling operator's mutant still executes, assert ≥1 Ignored *and* the
   sibling's status is not Ignored.
9. Rubocop, steep, full suite, both smoke rakes.

## Acceptance

- Backward compatible: every existing `# henitai:disable` usage (bare,
  trailing, method-scoped) behaves identically; existing directive specs
  pass unmodified.
- Per-operator disable suppresses exactly the named operators; sibling
  operators on the same line/method still generate live mutants.
- Regions: `disable-start`/`disable-end` cover the enclosed lines only;
  unmatched/unclosed/nested directives abort with file:line in the
  message, exit 2.
- Unknown operator names abort with exit 2 (no silent skip).
- Reasons appear in the JSON report (and thus the HTML report) on the
  Ignored mutant.
- Everything skipped remains visible as Ignored — nothing is silently
  dropped.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | directives grammar matrix (≥9 cases incl. all error paths); existing examples untouched |
| Unit | static filter: per-operator selectivity, region boundaries (line before/inside/after), reason attachment |
| Unit | reporter JSON reason serialization; non-directive Ignored mutants unchanged |
| CLI | unknown-name abort path (exit 2, message content) |
| Smoke | both fixtures: per-operator disable with live sibling assertion |
| Infra | `henitai operator list` output remains the user-facing source of valid names (doc cross-check in PR) |
