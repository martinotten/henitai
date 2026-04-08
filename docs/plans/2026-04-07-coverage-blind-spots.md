# Coverage Blind Spots in StaticFilter

**Status:** Ready for review  
**Scope:** `lib/henitai/static_filter.rb`

---

## Issue

After the fix in commit `30f2143` (check `start_line..end_line` instead of `start_line` only),
12 mutants in `Henitai::Result` are still reported as `NoCoverage` even though the methods
that contain them are exercised by the test suite. All 12 are interior lines of hash literals:

```
L106  StringLiteral   language: "ruby"                  (build_files_section)
L140  ArithmeticOperator  column: ... + 1               (line_column)
L158–167  StringLiteral  every value in stryker_status  (stryker_status)
```

The static filter gate treats `NoCoverage` mutants as untestable and skips execution for them,
so they never count toward the mutation score. This inflates the apparent MS and hides real
gaps.

---

## Analysis

### Root cause

Ruby's coverage engine does not emit a line-trace event for every syntactic line within a
hash or array literal. It records a hit for the line that initiates construction (often the
opening `{` or the `def` line), but individual key-value lines may receive no event at all,
even when the method is called repeatedly.

Evidence from `coverage/.resultset.json` for `result.rb`:

| Line | Content                              | Hits |
|------|--------------------------------------|------|
| 154  | `def stryker_status`                 | 1    |
| 157  | `{`                                  | 5    |
| 158  | `killed: "Killed",`                  | nil  |
| …    | …                                    | nil  |
| 167  | `}.fetch(status, "Pending")`         | nil  |
| 136  | `def line_column`                    | 1    |
| 139  | `line: mutant.location.fetch(…),`    | 10   |
| 140  | `column: mutant.location.fetch(…) + 1` | nil |

The commit `30f2143` fixed the "opening brace" variant: a multi-line hash used as a method's
return value, where `start_line` pointed at the uncovered `{`. That fix expanded `covered?`
to scan the full `start_line..end_line` range of the mutant node.

The remaining cases are different: the mutant's `start_line` and `end_line` are both on a
single interior line of a hash that Ruby never ticks. The range scan finds nothing and the
mutant is still marked `NoCoverage`.

### Why the existing approach cannot reach these lines

The node for `"Killed"` on line 158 has `start_line: 158, end_line: 158`. The range
`158..158` contains only that one uncovered line. No amount of widening the mutant's own
node range will help because Ruby genuinely records no hit for that line.

### What information is available

Each mutant carries a reference to its `subject`, and `subject.source_range` is the line
range of the enclosing method body (e.g. `154..168` for `stryker_status`). The coverage
report consistently records at least one hit somewhere in that range whenever the method is
called — the `def` line, the first statement, or the opening of a construct. If any line
in `source_range` is covered, the method was invoked and all of its non-conditional lines
are reachable.

### Scope of the fix

Using `source_range` as a fallback is a heuristic: it cannot distinguish an early-return
guard on line 1 from genuinely unreachable code later in the same method. For the static
filter this is intentional — the filter is a conservative pre-execution gate, not a
precision tool. False positives (running a test that contributes nothing) are far cheaper
than false negatives (permanently suppressing a real mutant as `NoCoverage`). The execution
stage will still kill or let-survive a mutant correctly once it runs.

No changes to SimpleCov configuration or the coverage report format are required.

---

## Plan

### Task 1 — Update `StaticFilter#covered?`

**File:** `lib/henitai/static_filter.rb`

Replace the current implementation:

```ruby
def covered?(mutant, coverage_lines)
  file = normalize_path(mutant.location[:file])
  covered = Array(coverage_lines[file])
  (mutant.location[:start_line]..mutant.location[:end_line]).any? do |line|
    covered.include?(line)
  end
end
```

With:

```ruby
def covered?(mutant, coverage_lines)
  file = normalize_path(mutant.location[:file])
  covered = Array(coverage_lines[file])

  return true if (mutant.location[:start_line]..mutant.location[:end_line]).any? { |line| covered.include?(line) }

  # Ruby's coverage engine does not tick every line within a hash or array
  # literal. Fall back to the enclosing method's full source range: if any
  # line in the method body was covered, the method was called and the
  # mutant's lines are reachable.
  source_range = mutant.subject&.source_range
  return false unless source_range

  source_range.any? { |line| covered.include?(line) }
end
```

### Task 2 — Add regression spec to `static_filter_spec.rb`

Add one example that exercises the fallback path: the mutant's own line is uncovered, but
another line in the subject's `source_range` is.

```ruby
it "keeps covered mutants pending when the mutant line is uncovered but the enclosing method range is" do
  Dir.mktmpdir do |dir|
    mutant = build_mutant("foo.bar")
    write_coverage_report(
      dir,
      {
        "RSpec" => {
          "coverage" => {
            File.join(dir, "sample.rb") => {
              "lines" => [1, nil, nil]   # line 1 covered, lines 2–3 not
            }
          }
        }
      }
    )

    mutant.location[:file]       = File.join(dir, "sample.rb")
    mutant.location[:start_line] = 2   # uncovered line
    mutant.location[:end_line]   = 2
    # subject source_range spans lines 1–3, which includes the covered line 1
    allow(mutant.subject).to receive(:source_range).and_return(1..3)

    Dir.chdir(dir) do
      described_class.new.apply([mutant], config)
    end

    expect(mutant.status).to eq(:pending)
  end
end
```

### Task 3 — Verify against the live report

Run:

```bash
bundle exec henitai run 'Henitai::Result'
```

Expected outcome: `No coverage` drops from 12 to 0 for the `Result` subject group. The
`scoring_summary` mutant and all `stryker_status` / `line_column` / `build_files_section`
interior-line mutants transition to `Killed` or `Survived`.

---

## Alternative: Raw Ruby coverage with method data

This approach fixes the root cause directly. Ruby's built-in `Coverage` API can collect
method coverage in addition to line and branch coverage. SimpleCov 0.22 does not expose a
`:method` criterion, so the viable path is to start Ruby coverage with `methods: true`
before SimpleCov initializes, then let SimpleCov write the raw resultset JSON as usual.

Henitai can then read the `methods` payload from the coverage report and expand each
covered method into the line range it owns.

### Verified behaviour (Ruby 4.0.2 + SimpleCov 0.22.0)

The following was confirmed experimentally against the actual project runtime.

**1 — Bootstrap ordering is safe.**

SimpleCov 0.22 calls `Coverage.start(start_arguments) unless Coverage.running?`
(`simplecov.rb:356`). If `Coverage.start(methods: true)` is called first, SimpleCov
detects `Coverage.running? == true` and skips its own start entirely. No conflict, no
double-start error. SimpleCov proceeds normally from that point.

**2 — SimpleCov 0.22 preserves the `methods` key in `.resultset.json`.**

`SimpleCov::ResultAdapter` (the only place coverage data is transformed before writing)
passes non-Array file data through unchanged:

```ruby
def adapt
  result.each_with_object({}) do |(file_name, cover_statistic), adapted_result|
    if cover_statistic.is_a?(Array)
      adapted_result.merge!(file_name => {"lines" => cover_statistic})
    else
      adapted_result.merge!(file_name => cover_statistic)  # ← hash passed through as-is
    end
  end
end
```

Because `Coverage.result` returns a Hash when started with named options, the `methods`
key is included in the hash and survives into the JSON unchanged.

Confirmed output for a file with one called and one uncalled method:

```json
{
  "lines":   [1, 1, 1, 1, null, 1, 0, null, null, null],
  "branches": {},
  "methods": {
    "[Henitai::CovTestProbe, :greet, 3, 4, 5, 7]": 1,
    "[Henitai::CovTestProbe, :uncalled, 6, 4, 8, 7]": 0
  }
}
```

**3 — Exact key format.**

Each key is the JSON serialization of Ruby's `[owner, name, start_line, start_col,
end_line, end_col]` array:

```
"[ClassName, :method_name, start_line, start_col, end_line, end_col]"
```

- `ClassName` — the full constant name as a string (e.g. `Henitai::Result`)
- `:method_name` — the method name with leading colon
- four integers — start line, start column, end line, end column (all 1-based)

The value is an integer call count. Zero means the method was never called.

To extract the line range, match the four trailing integers:

```ruby
if (m = key.match(/(\d+), (\d+), (\d+), (\d+)\]\z/))
  start_line, _start_col, end_line, _end_col = m.captures.map(&:to_i)
end
```

**4 — Detecting unavailability.**

When method coverage was not enabled, the `"methods"` key is simply absent from the file's
entry in `.resultset.json`. A `nil` guard on `file_coverage["methods"]` is the complete
fallback:

```ruby
methods = file_coverage["methods"]
next unless methods.is_a?(Hash)  # absent → skip; line coverage still applies
```

No version detection or feature flag is needed.

### Changes required

#### 1 — Coverage bootstrap

Start Ruby coverage before SimpleCov in the two places that produce baseline reports.

`spec/spec_helper.rb`:

```ruby
require "coverage"
Coverage.start(lines: true, branches: true, methods: true)

require "simplecov"
SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end
```

`lib/henitai/minitest_simplecov.rb` (same pattern — prepend the two `Coverage` lines before
`require "simplecov"`).

This is not a SimpleCov configuration change. It is a coverage bootstrap change so the VM
records method data from the first loaded line. Users who do not make this change will have
no `"methods"` key in their resultset; henitai will silently fall back to line-only
coverage as today.

#### 2 — `lib/henitai/static_filter.rb`

Add a private method that reads the `"methods"` section and merges covered method line
ranges into the existing `file → [covered_lines]` map. Call it from `coverage_lines_for`
after the line-based pass:

```ruby
def coverage_lines_for(config)
  coverage_report_path     = coverage_report_path(config)
  per_test_coverage_report = per_test_coverage_report_path(config)

  coverage_lines = coverage_lines_by_file(coverage_report_path)
  coverage_lines = merge_method_coverage(coverage_lines, coverage_report_path)
  return coverage_lines unless coverage_lines.empty?

  coverage_lines_from_test_lines(
    test_lines_by_file(per_test_coverage_report)
  )
end

def merge_method_coverage(coverage_lines, path)
  return coverage_lines unless File.exist?(path)

  JSON.parse(File.read(path)).each_value do |suite|
    suite.fetch("coverage", {}).each do |file, file_coverage|
      methods = file_coverage["methods"]
      next unless methods.is_a?(Hash)

      normalized = normalize_path(file)
      methods.each do |key, count|
        next unless count.to_i.positive?
        next unless (m = key.match(/(\d+), \d+, (\d+), \d+\]\z/))

        start_line, end_line = m.captures.map(&:to_i)
        coverage_lines[normalized] |= (start_line..end_line).to_a
      end
    end
  end

  coverage_lines.transform_values(&:sort)
end
```

No changes to `covered?` are required.

#### 3 — Specs

- Unit-test `merge_method_coverage` in `static_filter_spec.rb`:
  - a method with `count > 0` adds its full line range to the map
  - a method with `count: 0` is ignored
  - a file entry without `"methods"` is a no-op (fallback preserved)
- Confirm all existing `covered?` tests pass without modification.

### Trade-offs vs. the source-range heuristic

| | Source-range heuristic | Raw Ruby method coverage |
|---|---|---|
| User change | None | Add two lines to `spec_helper.rb` and `minitest_simplecov.rb` |
| Accuracy | Heuristic; over-approximates after early returns | Exact — reflects real call counts |
| Resultset format change | None | `"methods"` key added; backward-compatible |
| Fallback when absent | n/a | Silently degrades to line-only coverage |
| Per-test coverage path | Works via `source_range` | Still line-based for now (known gap) |
| Ruby version | None | Ruby 2.6+ — already the project target |

### Per-test coverage gap

`henitai_per_test.json` records only line numbers per test per source file. Method
coverage data is not available on that path. The blind spot therefore persists for
per-test-based coverage gating until `CoverageFormatter` is extended to also emit method
call counts. That extension is out of scope for this ADR.

### Mutant reference

Mutant avoids this class of problem by not using line coverage as the authority for test
selection. The Minitest integration uses explicit `cover` declarations, and the RSpec
integration selects tests by example-group prefix or explicit `mutant_expression`
metadata.

That design keeps selection tied to subject/test mapping rather than line hits. For
Henitai, the equivalent robust signal is Ruby method coverage, not a sibling-line fallback
heuristic.
