# Plan: `henitai analyze` — Complexity Hot-Spot Analysis

## Overview

Add a new subcommand `henitai analyze` that walks Ruby ASTs and reports
**hot spots** — files and methods whose structural complexity metrics
exceed configurable thresholds. The tool reuses Hen'i-tai's existing
`SourceParser` (Prism → Parser::AST) and `SubjectResolver`-style AST
walker, so it has zero new AST dependencies.

Analysed files are the same set as a mutation run (`includes:/excludes:` in
`.henitai.yml`), but the pipeline is read-only — no mutation, no test
execution, no coverage bootstrap.

```
$ henitai analyze
$ henitai analyze --since origin/main
$ henitai analyze --format json --output reports/complexity.json
$ henitai analyze --thresholds complexity=15,nesting=4
```

## Why now

Hen'i-tai already has rich AST plumbing. The mutation framework costs
nothing extra to walk; we just need a metric calculator sitting alongside
the existing node collector. Hot-spot analysis is a natural companion to
mutation testing — methods with high cyclomatic complexity tend to be the
ones most likely to harbour mutations that survive.

## Design

### CLI shape

Add `AnalyzeCommand` (mixed into `CLI` like `InitCommand` / `OperatorCommand`).

```
henitai analyze [options]
  --config PATH       .henitai.yml path
  --since GIT_REF     Only analyze files changed since GIT_REF
  --format FORMAT     terminal (default) | json | html
  --output PATH       Write JSON report to PATH
  --thresholds SPEC   Comma-separated key=value pairs overriding config
  --sort FIELD        Sort hot spots: complexity (default), nesting, loc, parameters
  --top N             Show only top N hot spots (default: 20)
  -h, --help          Show help
  -v, --version       Show version
```

Implementation: `lib/henitai/cli/analyze_command.rb`, registered in
`lib/henitai/cli.rb` under `case command when "analyze"`.

### Pipeline

```
Source files (includes/excludes)
  └── SubjectResolver.walk_with_metrics(node, ctx)  ← new
        └── Each :def / :defs / :block node
              └── Henitai::Analyze::MetricComputer.compute(method_node, file_path)
                    ├── cyclomatic
                    ├── cognitive
                    ├── nesting_depth
                    ├── parameters
                    ├── loc_per_file
                    └── maintainability_index (file-level)
  └── HotSpotSelector.filter(metrics, thresholds)
        └── Result object: FileMetricSet × MethodMetric
  └── Reporter::Analyze (terminal / json / html)
```

### New modules (all under `lib/henitai/analyze/`)

```
lib/henitai/analyze/
  metric_computer.rb        # Pure function: AST node → Hash[Symbol, Numeric]
  method_analyzer.rb        # Groups metrics by file/method
  hot_spot_selector.rb      # Filters/sorts by thresholds
  result.rb                  # Immutable result value object
  reporter/
    terminal.rb              # Coloured ranked table
    json.rb                  # Strtyker-compatible JSON shape
    html.rb                  # Optional HTML report
  file_analyzer.rb           # File-level metrics (LOC, MI, file cyclomatic sum)
```

### Complexity metrics

| Metric | What it measures | Reference |
|---|---|---|
| **Cyclomatic (McCabe)** | `1 + edges − nodes` over the method's decision graph | McCabe 1976 |
| **Cognitive** | Human readability penalty for nesting + structured keywords | Rath 2014 |
| **Nesting depth** | Deepest `if/while/unless/rescue` nesting inside the method | (custom) |
| **Parameter count** | Total positional + keyword + rest + block args | (custom) |
| **LOC** | Lines of code of the method body (excluding blank / comments) | (custom) |
| **Maintainability Index** | Composite of cyclomatic, LOC, and Halstead vol | Nagappan/Williams 2004 |
| **Branch count** | Raw count of `if`/`unless`/`case`/`when`/`while`/`until`/`and`/`or` nodes | (subset of cyclomatic) |

The four primary scores (`cyclomatic`, `cognitive`, `nesting`, `parameters`)
feed the `thresholds:` config so users can tune them independently.

### Threshold config

New section in `.henitai.yml`:

```yaml
analyze:
  thresholds:
    cyclomatic: 15          # methods above this are hot spots
    cognitive: 25
    nesting: 4              # max acceptable nesting depth
    parameters: 5           # max acceptable parameter count
  sort_by: cyclomatic       # cyclomatic | cognitive | nesting | loc | parameters
  top_n: 20
  include_methods_under:    # methods below ALL thresholds are skipped from output
    cyclomatic: 3
    cognitive: 5
    nesting: 2
    parameters: 2
```

CLI `--thresholds` overrides merge on top, keyed by metric name.

## Metrics specification (see `docs/plans/analyze_spec.md`)

Each metric gets a spec file. The spec writers use Prism-translated AST
strings directly (the same nodes `SourceParser.parse` produces), so there
is no need to generate a separate AST format.

```ruby
describe Henitai::Analyze::MetricComputer do
  it "counts cyclomatic complexity: simple method returns 1"
  it "counts cyclomatic: each branch adds 1"
  it "counts cognitive: nesting penalises exponentially"
  it "counts nesting: tracks deepest nesting depth"
  # ... etc.
end
```

## Reporter output examples

### Terminal (default)

```
Complexity hot spots
───────────────────────────
 #  File                          Method             Cycl  Cog  Nest  Params
 1  reporter.rb                   Terminal#report      22   31     6       4
 2  equivalence_detector.rb       #run                   18   28     5       3
 3  runner.rb                     #execute_mutants       16   24     4       6
 4  slot_scheduler.rb             #drain                 14   22     5       2
 5  coverage_bootstrapper.rb      #ensure!               12   19     4       1
...

File-level summary
───────────────────────────
 Total files analyzed: 67
 Files with hot spots: 12
 Top file (MI): configuration.rb    MI=38  cyclomatic=34
```

### JSON

Stays close to Stryker's schema so a future mutation+complexity combined
report can reuse the same structure:

```json
{
  "sessionId": "analyze-...",
  "files": [
    {
      "name": "lib/henitai/reporter.rb",
      "metrics": {
        "loc": 600,
        "cyclomatic": 42,
        "cognitive": 68,
        "nesting": 6,
        "maintainabilityIndex": 38
      },
      "methods": [
        {
          "name": "Terminal#report",
          "loc": 85,
          "cyclomatic": 22,
          "cognitive": 31,
          "nesting": 6,
          "parameters": 4,
          "hot": true
        }
      ]
    }
  ]
}
```

### HTML

Optional: emit a self-contained HTML report reusing the same
`mutation-test-elements` web component already referenced by the HTML
reporter, but feeding a complexity-data slot. Keep this V1 optional — only
the JSON reporter gets the promised Stryker schema.

## Integration with existing CLI

1. `CLI#run` (in `lib/henitai/cli.rb`) dispatches `"analyze"` → `analyze_command`.
2. `AnalyzeCommand` reads config, runs the pipeline, writes output.
3. No `Runner` involvement: we don't need mutant generation, execution, or
   history — just AST walking and metric computation.
4. The `--since` flag reuses `GitDiffAnalyzer` (already autoloaded).
5. The `--config` flag reuses `Configuration.load` from `CommandSupport`.

## Risks & open questions

| Risk | Mitigation |
|---|---|
| Cognitive complexity algorithm may drift from standard implementations | Spec the algorithm against known test cases from the original paper |
| Prism translations may produce nodes that `parser/current` walker doesn't expect | Write node-coverage specs; walk every `SourceParser.parse_file` output |
| Method extraction from AST bodies needs to handle blocks correctly | Reuse `SubjectResolver#collect_subject` to find `:def`/`:defs`/`:block` boundaries; metric computer operates on method bodies only |
| Performance on large repos | SourceParser caches parses by mtime; we just add another walk pass |

## Files to add / modify

**New:**
- `lib/henitai/analyze.rb` — module boundary + autoloader
- `lib/henitai/analyze/metric_computer.rb`
- `lib/henitai/analyze/method_analyzer.rb`
- `lib/henitai/analyze/hot_spot_selector.rb`
- `lib/henitai/analyze/result.rb`
- `lib/henitai/analyze/file_analyzer.rb`
- `lib/henitai/analyze/reporter/terminal.rb`
- `lib/henitai/analyze/reporter/json.rb`
- `lib/henitai/cli/analyze_command.rb`

**Modify:**
- `lib/henitai/cli.rb` — add `analyze_command` dispatch + autoload `AnalyzeCommand`
- `lib/henitai.rb` — autoload `Analyze` namespace
- `lib/henitai/configuration.rb` — add `analyze:` config section parsing + validation
- `assets/schema/henitai.schema.json` — add `analyze` block to JSON schema
- `lib/henitai/cli/options.rb` — add analyzer-specific option helpers to the `run` parser
  (or make a separate `AnalyzeOptions` module — depends on whether `analyze` shares options
  with `run`. Keep them separate for cleanliness.)

## Open questions

1. **Should `analyze` reuse `run` options (e.g. `--jobs`, `--operators`)?** No.
   These don't apply. The analyzer only needs config/since/format/thresholds.
2. **Should `--since` work on analyze?** Yes — useful for CI on PR diff.
3. **Should `--dry-run` work?** The analyze command already *is* a dry run
   (no execution). Skip it.
4. **Database / history store integration?** Out of scope for V1. Future:
   trend analysis on MI over time.
5. **Comparison to other tools (RUBYGrip, complexity gem)?** We keep our own
   implementation for two reasons: (a) AST is already Prism-translated so we
   don't need another parser, (b) metrics are cross-checked against the
   mutation candidates — hot methods should also be the mutation-heavy ones.
