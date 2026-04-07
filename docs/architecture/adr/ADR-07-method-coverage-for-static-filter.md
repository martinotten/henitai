# ADR-07: Raw Ruby Method Coverage for Static Coverage Filtering

Status: accepted

## Context

Henitai uses `StaticFilter` to mark mutants as `:no_coverage` before execution when the
coverage report shows that their source lines were never hit. That optimization is valuable,
but Ruby line coverage has a blind spot: interior lines in multi-line hash and array literals
can remain unmarked even when the enclosing method is exercised.

This shows up in `Henitai::Result`, where several mutants remain reported as `NoCoverage`
despite the test suite exercising the methods that contain them. A heuristic fallback based
on `Subject#source_range` would reduce false negatives, but it can also over-approximate and
mark truly uncovered mutants as covered.

The project already uses SimpleCov 0.22.0, but that version does not expose a `:method`
coverage criterion. Ruby's `Coverage` API does support method coverage directly, and the
following has been verified experimentally against Ruby 4.0.2 and SimpleCov 0.22.0:

- Starting `Coverage` with `methods: true` before SimpleCov is safe. SimpleCov 0.22 calls
  `Coverage.start(args) unless Coverage.running?`, so it skips its own start when coverage
  is already active. No conflict occurs.
- `SimpleCov::ResultAdapter` passes non-Array coverage data through unchanged. The
  `methods` key from `Coverage.result` is therefore preserved in `.resultset.json` without
  any change to SimpleCov configuration.
- Each method entry is keyed by the stringified Ruby array
  `"[ClassName, :method_name, start_line, start_col, end_line, end_col]"` and valued by
  its integer call count. A count of zero means the method was never called.
- When method coverage was not enabled the `"methods"` key is simply absent. A nil guard
  on `file_coverage["methods"]` is sufficient to degrade gracefully to line-only coverage.

## Decision

Use raw Ruby method coverage as the coverage signal for static filtering.

Concretely:

- start coverage with `lines: true`, `branches: true`, and `methods: true` before SimpleCov
  initializes
- keep SimpleCov as the report writer and formatter
- extend Henitai's coverage ingestion so it can read the `methods` payload from
  `.resultset.json`
- treat a mutant as covered when either its own line range is covered or the enclosing method
  has a positive method coverage count

This keeps the static gate conservative without relying on `Subject#source_range` as a
surrogate for execution.

## Considered Options

### Option A: Keep the current line-based check only

Status: rejected

This is the simplest implementation, but it leaves the current blind spot intact. Interior
lines in hash and array literals can still be marked `NoCoverage` even when the method is
executed.

### Option B: Add a `Subject#source_range` fallback

Status: rejected

This is a low-risk code change, but it is only a heuristic. It can misclassify early-return
methods or partially reachable method bodies as covered. That makes it a poor long-term
decision for a gate that exists specifically to suppress execution.

### Option C: Use raw Ruby method coverage

Status: accepted

This addresses the root cause instead of guessing from sibling lines. The method coverage
signal tells Henitai whether a method was executed, which is the right granularity for a
pre-execution coverage gate.

### Option D: Remove the static `NoCoverage` gate

Status: rejected

Running every mutant would be the most conservative option, but it would significantly
increase runtime and would throw away a useful optimization. Other frameworks avoid this by
using either explicit test-to-subject mappings or richer coverage analysis, not by removing
coverage gating entirely.

### Option E: Rebuild the optimization around explicit test-to-subject mapping

Status: deferred

This is the most robust architecture in the long run. Frameworks such as Mutant use explicit
subject/test mappings rather than coverage heuristics, and Stryker-style frameworks build a
mutant-to-test map during the dry run. Adopting that model in Henitai would be a larger
pipeline change and is better treated as a separate decision.

## Consequences

- the static filter no longer depends on a heuristic guess about the enclosing method body
- `spec/spec_helper.rb` and `lib/henitai/minitest_simplecov.rb` must call
  `Coverage.start(lines: true, branches: true, methods: true)` before `require "simplecov"`
- `StaticFilter` gains a `merge_method_coverage` step that expands called-method line ranges
  into the existing `file → [covered_lines]` map; `covered?` itself does not change
- if method coverage is unavailable (key absent from resultset), the filter silently falls
  back to line-only coverage — no user-visible error
- the per-test coverage path (`henitai_per_test.json`) remains line-based; the same blind
  spot persists there until `CoverageFormatter` is extended to emit method call counts —
  this is a known remaining gap and is out of scope for this ADR
- existing score semantics are preserved: this change only improves coverage classification
  before execution, it does not alter what counts as killed or survived

## Notes

- SimpleCov 0.22.0 only supports `:line` and `:branch` criteria via `enable_coverage`; this
  ADR bypasses that limitation by starting `Coverage` directly before SimpleCov initializes
- the `methods` key format is `"[ClassName, :method_name, start_line, start_col, end_line,
  end_col]"` — extract the line range with `/(\d+), \d+, (\d+), \d+\]\z/`
- the implementation should preserve the existing score semantics: this change only improves
  coverage classification before execution

## Related Documents

- [Architecture overview](../architecture.md)
- [Coverage blind spots plan](../../plans/2026-04-07-coverage-blind-spots.md)
