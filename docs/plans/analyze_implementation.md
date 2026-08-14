# Implementation plan: `henitai analyze`

This file bridges `analyze_command.md` (design) with actual file-by-file
coding. Follow the order; each step is a self-contained commit.

## Step 0 — Scaffold

1. Add `Analyze` autoload to `lib/henitai.rb`:
   ```ruby
   autoload :Analyze, "henitai/analyze"
   ```
2. Create `lib/henitai/analyze.rb` with the namespace declaration
   and an empty `module Henitai::Analyze`.

## Step 1 — `MetricComputer` (smallest, pure, deeply tested)

Write `lib/henitai/analyze/metric_computer.rb`.

```ruby
module Henitai
  module Analyze
    class MetricComputer
      def compute(node, file_path:)
        {
          file_path: file_path,
          cyclomatic: cyclomatic(node),
          cognitive: cognitive(node),
          nesting_depth: nesting_depth(node),
          parameter_count: parameter_count(node),
          loc: loc(node),
          halstead_volume: halstead_volume(node)
        }
      end
    end
  end
end
```

Each method walks a method-body AST subtree. The four primaries
(`cyclomatic`, `cognitive`, `nesting_depth`, `parameter_count`) are
per-method; `loc` and `halstead_volume` are file-level aggregates.

### Cyclomatic (McCabe)

```
CC = 1 + count(if) + count(unless) + count(while) + count(until)
     + count(for) + count(case) + count(rescue) + count(and) + count(or)
```

- A `case` node adds 1; `when` branches do not add individually (they are
  children of the `case` decision node — the McCabe formula counts the
  decision once at the `case` node).
- `and`/`or` at the top level of a condition count 1; if the condition itself
  is nested (e.g. `if (a && b)`) the inner `and` still counts as its own
  decision edge.

### Cognitive (Rath)

For each structured keyword node:

```
penalty = 1 + max(0, nesting_depth − 1)
```

- Nesting depth is counted from the **method body's** top level (i.e.
  `nesting_depth=0` inside a `:begin` body wrapper).
- `if`/`unless` at nesting 0 → +1.
- `if` at nesting 1 → +2.
- `else`/`elsif`/`when`/`rescue` branches add +1 (not nested).
- `&&`/`||` inside a condition add +1 per occurrence.
- Nested `def`/`defs`/`block` are transparent: they do not contribute their
  internal metrics to the parent method's cognitive score.
- Halstead-style `? :` conditionals add +1.

### Nesting depth

```
max_depth = max over all nested if/unless/while/until/case/rescue nodes
            of (distance_from_method_body_top + 1)
```

- Inner `def`/`defs`/`block` nodes reset the depth counter (they define a
  new scope).

### Parameter count

```
param_count = positional + keyword + rest + kwrest + block
```

For `:optarg`/`:kwarg`/`:kwrestarg`/`:blockarg`/`:restarg`, count 1 each.
Defaults (`:optarg`) count toward positional/keyword accordingly.

### LOC

Count lines in the method body that are neither blank nor contain a
standalone `#` comment. Use the source range:
```
source_lines = source_buffer.slice(location.expression)
```

### Halstead volume

```
V = N × log2(n)
```

Where `N` = total operator + operand occurrences and `n` = distinct
operators + distinct operands. Compute over AST nodes inside the method:

- Operators: `:send`, `:and`, `:or`, `:not`, `:if`, `:while`, `:case`,
  `:op_asgn`, `:send` (with various method names).
- Operands: `:int`, `:str`, `:sym`, `:float`, `:lvar`, `:ivar`, `:gvar`,
  `:const`, `:true`, `:false`, `:nil`, `:nil?`, `:self`.

This is an approximation. Halstead originally counted source-level tokens;
we count AST nodes of those categories. The resulting V is monotonic with
code size and enough for MI ranking.

### Maintainability Index

```
MI = (171 − 5.2·ln(V) − 0.23·CC − 16.2·ln(LOC)) × 100 / 100
```

Clamp to 0..100. `V` is Halstead volume (file-level), `CC` is cyclomatic
(file-level), `LOC` is file-level lines of code.

## Step 2 — `MethodAnalyzer`

Walks a file's AST, calls `MetricComputer#compute` on each method body,
and returns an array of `MethodMetric` value objects.

Use the same strategy as `SubjectResolver#collect_subject`: iterate over
`:def`/`:defs`/`:block` nodes while tracking the enclosing namespace and
singleton context.

```ruby
MethodMetric = Struct.new(
  :name, :namespace, :method_type, :file_path, :source_range,
  :cyclomatic, :cognitive, :nesting_depth, :parameter_count,
  :loc, :halstead_volume, :source_code_line
) do
  def hot?(thresholds)
    thresholds.any? do |key, max|
      (send(key) || 0) > max
    end
  end
end
```

## Step 3 — `HotSpotSelector`

```ruby
class HotSpotSelector
  SORT_KEYS = %i[cyclomatic cognitive nesting_depth parameter_count loc].freeze

  def initialize(thresholds: {}, sort_by: :cyclomatic, top_n: 20)
    @thresholds = thresholds
    @sort_by = SORT_KEYS.include?(sort_by) ? sort_by : :cyclomatic
    @top_n = top_n
  end

  def select(method_metrics)
    return [] if @thresholds.empty?

    filtered = method_metrics.select { |m| m.hot?(@thresholds) }
    sorted = filtered.sort_by { |m| -m.send(@sort_by).to_i }
    sorted.first(@top_n)
  end
end
```

## Step 4 — `FileAnalyzer`

```ruby
class FileAnalyzer
  def analyze(file_path, method_metrics)
    file_loc = count_file_loc(file_path)
    file_cc = method_metrics.sum(&:cyclomatic)
    file_hv = method_metrics.sum(&:halstead_volume)
    FileMetric.new(
      file_path:, file_loc:,
      cyclomatic: file_cc,
      halstead_volume: file_hv,
      maintainability_index: maintainability_index(file_hv, file_cc, file_loc),
      methods: method_metrics
    )
  end
end
```

## Step 5 — `Result` (Analyze)

```ruby
class Result
  attr_reader :file_metrics, :methods, :duration, :started_at

  def initialize(file_metrics:, methods:, started_at:, finished_at:)
    @file_metrics = file_metrics
    @methods = methods
    @duration = finished_at - started_at
    @started_at = started_at
  end

  def total_files
    file_metrics.size
  end

  def hot_method_count
    methods.count(&:hot?)
  end

  def summary
    {
      total_files: total_files,
      total_methods: methods.size,
      hot_methods: hot_method_count,
      duration: format("%.2fs", duration)
    }
  end
end
```

## Step 6 — Reporters

### Terminal reporter

```ruby
class Reporter::Analyze::Terminal
  def report(result)
    puts "Complexity hot spots".center(60, "─")
    puts result.methods.map.with_index(1) { |m, i|
      format("%2d  %-30s  %-30s  %4d  %4d  %4d  %4d",
             i, path_short(m.file_path), method_label(m),
             m.cyclomatic, m.cognitive, m.nesting_depth, m.parameter_count)
    }.join("\n")
    puts "─".center(60, "─")
    puts result.summary.to_s
  end
end
```

Colour by hot metric: red for any metric > threshold, yellow for near.

### JSON reporter

Stays close to Stryker's schema shape.

```ruby
class Reporter::Analyze::Json
  def report(result)
    payload = {
      sessionId: "analyze-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}",
      files: result.file_metrics.map { |f| file_schema(f) }
    }
    if @output_path
      FileUtils.mkdir_p(File.dirname(@output_path))
      File.write(@output_path, JSON.pretty_generate(payload))
    else
      puts JSON.pretty_generate(payload)
    end
  end
end
```

## Step 7 — CLI integration

1. `lib/henitai/cli/analyze_command.rb`:
   ```ruby
   module Henitai
     class CLI
       module AnalyzeCommand
         def analyze_command
           options = parse_analyze_options
           return if @command_halted

           config = load_config(options)
           result = run_analyze_pipeline(options, config)
           report_analyze(result)
           exit(analyze_exit_status(result, options))
         rescue StandardError => e
           warn "#{e.class}: #{e.message}"
           exit 2
         end
       end
     end
   end
   ```

2. Register in `lib/henitai/cli.rb`:
   ```ruby
   include AnalyzeCommand
   when "analyze" then analyze_command
   ```

3. Add analyzer option parsers (`lib/henitai/cli/analyze_options.rb`):
   ```ruby
   def parse_analyze_options
     options = {}
     build_analyze_option_parser(options).parse!(@argv)
     options
   end

   def build_analyze_option_parser(options)
     OptionParser.new do |opts|
       opts.banner = "Usage: henitai analyze [options]"
       add_config_option(opts, options)
       add_since_option(opts, options)
       add_format_option(opts, options)
       add_output_option_analyze(opts, options)
       add_thresholds_option(opts, options)
       add_sort_option(opts, options)
       add_top_option(opts, options)
       add_help_option(opts)
       add_version_option(opts)
     end
   end
   ```

## Step 8 — Configuration

Add `analyze:` block to `Configuration` and `ConfigurationValidator`.

```yaml
analyze:
  thresholds:
    cyclomatic: 15
    cognitive: 25
    nesting: 4
    parameters: 5
  sort_by: cyclomatic
  top_n: 20
  include_methods_under:
    cyclomatic: 3
    cognitive: 5
    nesting: 2
    parameters: 2
```

Validator: ensure all keys are known, values are positive numbers where
expected, `sort_by` is one of the four primary metrics.

Schema: add to `assets/schema/henitai.schema.json` under the existing
`mutation:` block sibling.

## Step 9 — Tests (spec ordering)

1. `metric_computer_spec.rb` — all four primary metrics (fastest, pure)
2. `method_analyzer_spec.rb` — groups correctly
3. `hot_spot_selector_spec.rb` — filtering, sorting, top-N
4. `file_analyzer_spec.rb` — file aggregates
5. `result_spec.rb` — value object
6. `reporter/terminal_spec.rb` — terminal output shape
7. `reporter/json_spec.rb` — JSON output shape
8. `analyze_command_spec.rb` — CLI integration

## Step 10 — RuboCop pass + README update

- Run `bundle exec rubocop lib/henitai/analyze/` and fix offenses.
- Update `README.md` "Commands" section with `analyze`.
- Update `CHANGELOG.md` with the new feature.

## References

- McCabe 1976: "A Complexity Measure" — McCabe's formula
- Rath 2014: "Cognitive Complexity" — cognitive scoring rules
- Nagappan/Williams 2004: "Predicting faults using the combined
  effect of code and process metrics" — Maintainability Index formula
- Repository: `docs/research/` for mutation testing literature
