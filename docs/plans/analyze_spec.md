# Spec plan: `henitai analyze` complexity metrics

Each metric gets its own spec file. Specs exercise the metric against
AST strings that `SourceParser.parse_file` produces (i.e. Prism → Parser
translations).

```
spec/henitai/analyze/
  metric_computer_spec.rb    # All four primary metric computations
  method_analyzer_spec.rb    # Grouping by file/method, result shape
  hot_spot_selector_spec.rb  # Filtering + sorting + top-N
  file_analyzer_spec.rb      # File-level aggregates (LOC, MI, file cyclomatic)
  result_spec.rb             # Value object construction, nil/safe accessors
  reporter/
    terminal_spec.rb           # Terminal column layout, colours, sort
    json_spec.rb               # JSON schema emission
  analyze_command_spec.rb      # CLI integration end-to-end
```

## `MetricComputer`

Tests the pure function:

```ruby
describe Henitai::Analyze::MetricComputer do
  let(:computer) { described_class.new }

  describe "#cyclomatic" do
    it "returns 1 for a straight-line method"
    it "adds 1 per if/unless branch"
    it "adds 1 per while/until loop"
    it "adds 1 per for loop"
    it "adds 1 per case/when branch"
    it "adds 1 per rescue clause"
    it "adds 1 per and/or short-circuit"
    it "does not count nested def (counts child def at top level)"
    it "handles ternary-style ? :"
  end

  describe "#cognitive" do
    # per Rath: +1 for each if/else/while/unless/until/for/case/when,
    #           +1 per binary op inside a condition,
    #           +n per nesting level n deep
    it "returns 0 for a trivial method"
    it "adds 1 per if/unless with no nesting"
    it "adds 2 per if at 1-level nesting (1+1)"
    it "adds 3 per if at 2-level nesting (1+2)"
    it "adds 1 per else/elsif/when clause"
    it "adds 1 per &&/|| in any condition"
    it "adds 0 per nested method def (no cognitive penalty for inner defs)"
  end

  describe "#nesting_depth" do
    it "returns 0 for a trivial method"
    it "returns 1 per if/unless/while/until layer"
    it "returns 1 per case/when layer"
    it "returns 1 per rescue layer"
    it "tracks max, not total"
    it "does not count inner def nesting as nesting"
  end

  describe "#parameters" do
    it "counts positional args"
    it "counts keyword args"
    it "counts rest args (*)"
    it "counts kwrest args (**)"
    it "counts block arg (&)"
    it "counts defaults once"
  end

  describe "#loc" do
    it "counts non-blank, non-comment lines in the method body"
  end

  describe "#maintainability_index" do
    # MI = (171 − 5.2·ln(HV) − 0.23·CC − 16.2·ln(LOC)) · 100 / 100
    it "decreases with higher cyclomatic"
    it "decreases with higher LOC"
    it "returns max 100 for a trivial method"
    it "returns <0 for large deeply-nested methods"
  end

  describe "#file_cyclomatic" do
    it "sums cyclomatic across all methods"
    it "does not count metrics from inner defs"
  end

  describe "#file_maintainability_index" do
    it "uses file-level LOC and Halstead volume"
  end
end
```

## `MethodAnalyzer`

```ruby
describe Henitai::Analyze::MethodAnalyzer do
  it "returns one MethodMetric per :def/:defs/:block node"
  it "inherits the enclosing namespace for block-defined methods"
  it "sets singleton_context flag for define_method + sclass"
  it "records source location"
  it "returns an empty array when no methods are found"
end
```

## `HotSpotSelector`

```ruby
describe Henitai::Analyze::HotSpotSelector do
  it "returns methods whose any primary metric exceeds its threshold"
  it "applies --thresholds overrides"
  it "sorts by the configured sort key, descending"
  it "limits to top N"
  it "does not include methods below include_methods_under"
  it "raises on unknown sort key"
  it "raises on negative top_n"
end
```

## `FileAnalyzer`

```ruby
describe Henitai::Analyze::FileAnalyzer do
  it "aggregates file-level LOC (non-blank, non-comment)"
  it "aggregates file cyclomatic across methods"
  it "computes file Halstead volume from method Halstead sums"
  it "computes file MI"
  it "reports file path + metrics + methods array"
end
```

## `Result` (Analyze)

```ruby
describe Henitai::Analyze::Result do
  it "builds from MethodMetric list + FileMetric list"
  it "exposes total_methods, hot_method_count, total_files"
  it "returns empty summary when no hot spots"
  it "returns top method for each metric (e.g. highest cyclomatic)"
end
```

## CLI integration

```ruby
describe Henitai::CLI, "analyze" do
  it "accepts --format terminal|json|html"
  it "accepts --since GIT_REF"
  it "accepts --thresholds cyclomatic=20"
  it "accepts --top 50"
  it "accepts --sort cognitive"
  it "accepts --output PATH"
  it "writes JSON to PATH with --output"
  it "writes JSON to stdout when --format json with no --output"
  it "applies analyzer thresholds overrides"
  it "exits 0 on success"
  it "exits 1 when hot spots exceed count > 0"
  it "exits 2 on configuration error"
end
```

## Notes

- Metrics are **independent** of `SourceParser`'s AST translation layer;
  every spec calls `Henitai::SourceParser.parse(source)` and feeds the
  returned node tree to `MetricComputer`.
- Reusing SourceParser means Prism-translated AST quirks (e.g. `:block`
  wrapping around `:def` for methods with blocks) are handled automatically
  as long as the walker respects the same tree shape.
- Halstead volume derives from `detectable_tokens` inside a method: count
  distinct operators / operands and their frequencies. We can compute this
  from `Parser::AST::Node` types (e.g. `:send`, `:lit`, `:int`).
- The Cognitive complexity algorithm matches Sebastian Rath's published
  rules exactly:
  - +1 for `if`/`unless`/`while`/`until`/`for`/`case`/`when`/`rescue`
  - +n for each nesting level `n` (0-indexed; root level is 0)
  - +1 for `else`/`elsif`/`else if`/`elsif` (branches, not nesting)
  - +1 for each `&&`/`||` in a condition
