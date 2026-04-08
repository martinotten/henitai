# Method Coverage Static Filter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate false `NoCoverage` results for interior lines of hash/array literals by
supplementing line coverage with Ruby method call counts from `.resultset.json`.

**Architecture:** Start `Coverage` with `methods: true` before SimpleCov in both bootstrap
files so the resultset JSON gains a `"methods"` key. Add `merge_method_coverage` to
`StaticFilter#coverage_lines_for` to expand called-method line ranges into the existing
`file → [covered_lines]` map. `covered?` itself does not change. When `"methods"` is absent
the filter silently falls back to line-only coverage.

**Tech Stack:** Ruby 4.0.2, SimpleCov 0.22.0, RSpec

---

## Background: what the resultset looks like after this change

Today a file entry in `.resultset.json` looks like:

```json
"lib/henitai/result.rb": {
  "lines":    [1, null, 3, ...],
  "branches": { ... }
}
```

After enabling method coverage it gains a third key:

```json
"lib/henitai/result.rb": {
  "lines":    [1, null, 3, ...],
  "branches": { ... },
  "methods": {
    "[Henitai::Result, :stryker_status, 154, 4, 168, 5]": 5,
    "[Henitai::Result, :line_column, 136, 4, 142, 5]": 10,
    "[Henitai::Result, :uncalled_example, 200, 4, 205, 5]": 0
  }
}
```

Each key encodes `[ClassName, :method_name, start_line, start_col, end_line, end_col]`.
The value is the integer call count. Zero means the method was never called.

`SimpleCov::ResultAdapter` already passes non-Array file data through unchanged, so no
SimpleCov change is needed to get this key into the file. Verified on Ruby 4.0.2 +
SimpleCov 0.22.0.

---

## Task 1: Enable method coverage in the RSpec bootstrap

**Files:**
- Modify: `spec/spec_helper.rb:1-8`

The goal is to start `Coverage` with `methods: true` before SimpleCov initializes.
SimpleCov checks `Coverage.running?` before calling `Coverage.start`, so starting it first
is safe — SimpleCov skips its own start.

**Step 1: Write the failing spec**

There is no automated spec for the bootstrap itself. Skip to step 3.

**Step 2: Apply the change**

Edit `spec/spec_helper.rb`. Add two lines before `require "simplecov"`:

```ruby
# frozen_string_literal: true

require "coverage"
Coverage.start(lines: true, branches: true, methods: true)

require "simplecov"
SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end
```

**Step 3: Verify the suite still passes**

```bash
bundle exec rspec
```

Expected: same pass count as before, no new errors.

**Step 4: Verify the resultset now contains `"methods"`**

```bash
ruby -rjson -e '
  data = JSON.parse(File.read("coverage/.resultset.json"))
  data.each_value do |suite|
    suite.fetch("coverage", {}).each do |file, cov|
      next unless file.include?("static_filter")
      puts cov.keys.inspect
      break
    end
  end
'
```

Expected output: `["lines", "branches", "methods"]`

**Step 5: Commit**

```bash
git add spec/spec_helper.rb
git commit -m "feat: enable method coverage in RSpec bootstrap"
```

---

## Task 2: Enable method coverage in the Minitest bootstrap

**Files:**
- Modify: `lib/henitai/minitest_simplecov.rb:1-12`

This file is injected into Minitest baseline subprocesses. It currently calls
`require "simplecov"` directly. Apply the same bootstrap pattern as Task 1.

**Step 1: Apply the change**

Edit `lib/henitai/minitest_simplecov.rb`:

```ruby
# frozen_string_literal: true

# Injected by henitai into the Minitest baseline subprocess to collect
# line coverage and write it as a SimpleCov-compatible .resultset.json.
#
# Must be required before any application code is loaded so that Coverage
# tracking is active from the first line.

require "coverage"
Coverage.start(lines: true, branches: true, methods: true)

require "simplecov"

SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
SimpleCov.start
```

**Step 2: Run the suite to confirm nothing broke**

```bash
bundle exec rspec
```

Expected: green.

**Step 3: Commit**

```bash
git add lib/henitai/minitest_simplecov.rb
git commit -m "feat: enable method coverage in Minitest bootstrap"
```

---

## Task 3: Parse method coverage in `StaticFilter`

**Files:**
- Modify: `lib/henitai/static_filter.rb:30-40` (`coverage_lines_for`)
- Modify: `lib/henitai/static_filter.rb` (add `merge_method_coverage` private method)
- Test: `spec/henitai/static_filter_spec.rb`

### Step 1: Write a failing spec for the absent-`methods`-key case

This is the no-op / backward-compatibility case. Open
`spec/henitai/static_filter_spec.rb` and add after the existing coverage specs:

```ruby
it "is unaffected when the resultset has no methods key" do
  Dir.mktmpdir do |dir|
    mutant = build_mutant("foo.bar")
    write_coverage_report(
      dir,
      {
        "RSpec" => {
          "coverage" => {
            File.join(dir, "sample.rb") => {
              "lines" => [nil, 1, nil]
            }
          }
        }
      }
    )

    mutant.location[:file]       = File.join(dir, "sample.rb")
    mutant.location[:start_line] = 3
    mutant.location[:end_line]   = 3

    Dir.chdir(dir) do
      described_class.new.apply([mutant], config)
    end

    expect(mutant.status).to eq(:no_coverage)
  end
end
```

**Step 2: Run to confirm it passes already** (it should — no code changed yet)

```bash
bundle exec rspec spec/henitai/static_filter_spec.rb
```

Expected: green. This is a characterisation spec; it must pass before and after.

### Step 3: Write a failing spec for the positive-count case

Add immediately after the spec from Step 1:

```ruby
it "treats mutant lines as covered when the enclosing method has a positive call count" do
  Dir.mktmpdir do |dir|
    mutant = build_mutant("foo.bar")
    write_coverage_report(
      dir,
      {
        "RSpec" => {
          "coverage" => {
            File.join(dir, "sample.rb") => {
              "lines" => [1, nil, nil],
              "methods" => {
                "[Example, :example, 1, 0, 3, 3]" => 5
              }
            }
          }
        }
      }
    )

    mutant.location[:file]       = File.join(dir, "sample.rb")
    mutant.location[:start_line] = 2   # nil in lines — blind spot
    mutant.location[:end_line]   = 2

    Dir.chdir(dir) do
      described_class.new.apply([mutant], config)
    end

    expect(mutant.status).to eq(:pending)
  end
end
```

**Step 4: Run to confirm it fails**

```bash
bundle exec rspec spec/henitai/static_filter_spec.rb -e "positive call count"
```

Expected: FAIL — mutant gets `:no_coverage` because `merge_method_coverage` doesn't exist yet.

### Step 5: Write a failing spec for the zero-count case

Add after the spec from Step 3:

```ruby
it "does not cover mutant lines when the enclosing method has a zero call count" do
  Dir.mktmpdir do |dir|
    mutant = build_mutant("foo.bar")
    write_coverage_report(
      dir,
      {
        "RSpec" => {
          "coverage" => {
            File.join(dir, "sample.rb") => {
              "lines" => [nil, nil, nil],
              "methods" => {
                "[Example, :example, 1, 0, 3, 3]" => 0
              }
            }
          }
        }
      }
    )

    mutant.location[:file]       = File.join(dir, "sample.rb")
    mutant.location[:start_line] = 2
    mutant.location[:end_line]   = 2

    Dir.chdir(dir) do
      described_class.new.apply([mutant], config)
    end

    expect(mutant.status).to eq(:no_coverage)
  end
end
```

**Step 6: Run to confirm it passes already** (zero count → no lines added → still no_coverage)

```bash
bundle exec rspec spec/henitai/static_filter_spec.rb -e "zero call count"
```

Expected: green. This will stay green once we implement — confirming we don't over-count.

### Step 7: Implement `merge_method_coverage`

In `lib/henitai/static_filter.rb`, update `coverage_lines_for` and add a new private
method.

**Change `coverage_lines_for` (lines 30-40):**

```ruby
def coverage_lines_for(config)
  coverage_report_path = coverage_report_path(config)
  per_test_coverage_report_path = per_test_coverage_report_path(config)

  coverage_lines = coverage_lines_by_file(coverage_report_path)
  coverage_lines = merge_method_coverage(coverage_lines, coverage_report_path)
  return coverage_lines unless coverage_lines.empty?

  coverage_lines_from_test_lines(
    test_lines_by_file(per_test_coverage_report_path)
  )
end
```

**Add `merge_method_coverage` to the private section** (after `covered_lines`, around line 123):

```ruby
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

The regex `/(\d+), \d+, (\d+), \d+\]\z/` captures the two line numbers (start and end)
from the trailing four integers in the key, ignoring the two column numbers.

### Step 8: Run the target spec to confirm it passes

```bash
bundle exec rspec spec/henitai/static_filter_spec.rb
```

Expected: all green, including the new "positive call count" example.

### Step 9: Run the full suite

```bash
bundle exec rspec
```

Expected: green.

### Step 10: Commit

```bash
git add lib/henitai/static_filter.rb spec/henitai/static_filter_spec.rb
git commit -m "feat: merge method coverage into static filter line map"
```

---

## Task 4: Verify against the live mutation report

**Step 1: Regenerate the baseline coverage**

The `.resultset.json` on disk was produced before the bootstrap change. Regenerate it:

```bash
bundle exec rspec
```

**Step 2: Run mutation testing on `Henitai::Result`**

```bash
bundle exec henitai run 'Henitai::Result'
```

**Expected outcome:**

```
No coverage  0
```

All 12 previously-suppressed mutants (`stryker_status` string values, `line_column` `+ 1`,
`build_files_section` `language:` line) should now execute. They will each resolve to
`Killed` or `Survived` depending on whether the test suite catches them.

If any remain `NoCoverage`, inspect the resultset entry for that file:

```bash
ruby -rjson -e '
  data = JSON.parse(File.read("coverage/.resultset.json"))
  data.each_value do |suite|
    suite.fetch("coverage", {}).each do |file, cov|
      next unless file.include?("result.rb")
      puts "methods keys: " + cov.fetch("methods", {}).keys.first(3).inspect
    end
  end
'
```

**Step 3: Commit if clean**

```bash
git add coverage/.resultset.json   # only if you want to commit the regenerated report
git commit -m "test: regenerate coverage baseline with method data"
```

---

## What NOT to do

- Do not change `covered?` — the line-range check is still correct and still needed for the
  opening-brace case fixed in `30f2143`.
- Do not add method coverage to the per-test path (`henitai_per_test.json`). That is a
  separate ADR item.
- Do not add `enable_coverage :method` to the `SimpleCov.start` block — SimpleCov 0.22
  does not support that criterion and would raise an error.
