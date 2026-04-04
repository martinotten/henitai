# integration.rb Coverage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Increase mutation-killing test coverage for `lib/henitai/integration.rb`, with priority on the surviving mutations reported in `reports/mutation-report.json` and the adjacent `NoCoverage` gaps that sit on the same behavior seams.

**Architecture:** Keep production behavior stable and raise confidence through characterization specs. Favor direct, narrow tests for helper seams such as log capture, file selection, and Minitest setup instead of pushing more behavior through the existing fork-heavy integration specs. This stays aligned with the process-isolation boundary from ADR-02 and the child-log artifact contract from ADR-06.

**Tech Stack:** Ruby 4.0.2, RSpec, mutation report in `reports/mutation-report.json`, integration code in `lib/henitai/integration.rb`

---

## Mutation Targets

Prioritize these surviving mutations first:

- `lib/henitai/integration.rb:73`, `:78`, `:82`, `:94`
  `ScenarioLogSupport` restore and coverage-dir helpers.
- `lib/henitai/integration.rb:175`, `:198`, `:246`
  RSpec suite/log helper seams.
- `lib/henitai/integration.rb:328`, `:329`, `:334`, `:337`, `:355`, `:365`
  fallback selection and require-resolution helpers.
- `lib/henitai/integration.rb:441`, `:442`, `:453`
  Minitest load-path and test-file discovery.

Secondary `NoCoverage` targets to collect while touching the same area:

- `lib/henitai/integration.rb:36`, `:58-63`, `:108`, `:116`, `:121`, `:131`
- `lib/henitai/integration.rb:238`, `:257-270`, `:313`, `:320-323`, `:369`, `:375-378`
- `lib/henitai/integration.rb:406-421`, `:447-448`

## General Rules For Execution

- Do not start by changing `lib/henitai/integration.rb`.
- Add or tighten a spec first.
- Run the focused spec file after each change.
- After a spec cluster is green, rerun the narrow mutation slice with:

```bash
bundle exec henitai run 'Henitai::Integration*'
```

- Only change production code if a new characterization spec exposes a real defect in current behavior.

### Task 1: Cover `ScenarioLogSupport` Directly

**Files:**
- Create: `spec/henitai/integration/scenario_log_support_spec.rb`
- Test target: `lib/henitai/integration.rb:23-96`

**Step 1: Write the failing spec**

Add direct examples for:

```ruby
RSpec.describe Henitai::Integration::ScenarioLogSupport do
  it "restores the original coverage dir when one already exists" do
    support = described_class.new
    ENV["HENITAI_COVERAGE_DIR"] = "existing-dir"

    support.with_coverage_dir("mutant-1") do
      expect(ENV["HENITAI_COVERAGE_DIR"]).to eq("reports/mutation-coverage/mutant-1")
    end

    expect(ENV["HENITAI_COVERAGE_DIR"]).to eq("existing-dir")
  end

  it "removes HENITAI_COVERAGE_DIR when no original value existed" do
    support = described_class.new
    ENV.delete("HENITAI_COVERAGE_DIR")

    support.with_coverage_dir("mutant-2") { }

    expect(ENV).not_to have_key("HENITAI_COVERAGE_DIR")
  end

  it "uses HENITAI_REPORTS_DIR when building the mutation coverage path" do
    support = described_class.new
    ENV["HENITAI_REPORTS_DIR"] = "tmp/reports"

    support.with_coverage_dir("mutant-3") do
      expect(ENV["HENITAI_COVERAGE_DIR"]).to eq("tmp/reports/mutation-coverage/mutant-3")
    end
  end
end
```

Add a second context for stream handling with doubles or tempfiles:

```ruby
it "reopens stdout and stderr back to their original streams" do
  support = described_class.new
  output_files = {
    original_stdout: instance_double(IO),
    original_stderr: instance_double(IO),
    stdout_file: instance_double(File, close: nil),
    stderr_file: instance_double(File, close: nil)
  }

  expect($stdout).to receive(:reopen).with(output_files[:original_stdout])
  expect($stderr).to receive(:reopen).with(output_files[:original_stderr])

  support.close_child_output(output_files)
end
```

**Step 2: Run test to verify the new coverage surface**

Run:

```bash
bundle exec rspec spec/henitai/integration/scenario_log_support_spec.rb
```

Expected: the new file runs, and any failures point to the exact helper seam being characterized.

**Step 3: Write minimal implementation**

Only patch `lib/henitai/integration.rb` if one of the new examples exposes a real behavior bug. If current behavior is already correct, keep production code unchanged and keep expanding the spec file until lines `31-39`, `42-88`, and `93-95` are covered.

**Step 4: Run test and mutation slice**

Run:

```bash
bundle exec rspec spec/henitai/integration/scenario_log_support_spec.rb
bundle exec henitai run 'Henitai::Integration*'
```

Expected: survivors at lines `73`, `78`, `82`, and `94` move to `Killed` or at minimum become covered.

**Step 5: Commit**

```bash
git add spec/henitai/integration/scenario_log_support_spec.rb
git commit -m "test: cover integration scenario log helpers"
```

### Task 2: Cover Integration Entry Points And RSpec Log Helpers

**Files:**
- Modify: `spec/henitai/integration/rspec_spec.rb`
- Test target: `lib/henitai/integration.rb:105-131`, `174-270`

**Step 1: Write the failing spec**

Add focused examples for:

```ruby
it "resolves known integration names" do
  expect(Henitai::Integration.for("rspec")).to eq(Henitai::Integration::Rspec)
  expect(Henitai::Integration.for("minitest")).to eq(Henitai::Integration::Minitest)
end

it "raises a helpful error for an unknown integration" do
  expect { Henitai::Integration.for("unknown") }
    .to raise_error(ArgumentError, "Unknown integration: unknown. Available: rspec")
end

it "keeps Base abstract methods unimplemented" do
  base = Henitai::Integration::Base.new

  expect { base.select_tests(nil) }.to raise_error(NotImplementedError)
  expect { base.test_files }.to raise_error(NotImplementedError)
  expect { base.run_mutant(mutant: nil, test_files: [], timeout: 1.0) }
    .to raise_error(NotImplementedError)
end

it "returns an empty string when a log file is missing" do
  integration = described_class.new
  expect(integration.send(:read_log_file, "does/not/exist.log")).to eq("")
end

it "builds baseline scenario log paths under reports/mutation-logs" do
  integration = described_class.new

  expect(integration.send(:scenario_log_paths, "baseline")).to eq(
    stdout_path: "reports/mutation-logs/baseline.stdout.log",
    stderr_path: "reports/mutation-logs/baseline.stderr.log",
    log_path: "reports/mutation-logs/baseline.log"
  )
end

it "formats combined logs with stdout and stderr sections only when present" do
  integration = described_class.new

  expect(integration.send(:combined_log, "out\n", "")).to eq("stdout:\nout\n")
  expect(integration.send(:combined_log, "", "err\n")).to eq("stderr:\nerr\n")
end

it "delegates pause to sleep" do
  integration = described_class.new
  expect(integration).to receive(:sleep).with(0.25)
  integration.send(:pause, 0.25)
end
```

Also add a small suite-command example:

```ruby
it "uses bundle exec rspec for the baseline suite command" do
  integration = described_class.new
  expect(integration.send(:suite_command, ["spec/foo_spec.rb"])).to eq(
    ["bundle", "exec", "rspec", "spec/foo_spec.rb"]
  )
end
```

**Step 2: Run test to verify the new coverage surface**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb
```

Expected: failures, if any, point to the exact factory, log-helper, or command-helper contract.

**Step 3: Write minimal implementation**

Patch `lib/henitai/integration.rb` only if a new example exposes a real contract bug. Otherwise leave production code untouched.

**Step 4: Run test and mutation slice**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb
bundle exec henitai run 'Henitai::Integration::Rspec*'
```

Expected: the survivors at lines `175`, `198`, and `246` are gone, and the `NoCoverage` gaps around `108`, `116`, `121`, `131`, `238`, and `257-270` are reduced.

**Step 5: Commit**

```bash
git add spec/henitai/integration/rspec_spec.rb
git commit -m "test: cover integration entry points and rspec log helpers"
```

### Task 3: Tighten Fallback Test Selection And Require Resolution

**Files:**
- Modify: `spec/henitai/integration/rspec_spec.rb`
- Modify: `spec/henitai/integration/rspec_select_tests_spec.rb`
- Test target: `lib/henitai/integration.rb:320-379`

**Step 1: Write the failing spec**

Add direct helper specs that isolate each surviving branch:

```ruby
it "orders selection patterns by longest first and removes duplicates" do
  subject = instance_double(
    Henitai::Subject,
    expression: "Sample::Thing#value",
    namespace: "Sample::Thing"
  )

  expect(described_class.new.send(:selection_patterns, subject)).to eq(
    ["Sample::Thing#value", "Sample::Thing"]
  )
end

it "matches a source file when only the basename is present in the spec content" do
  integration = described_class.new
  allow(File).to receive(:read).and_return("require_relative \"../lib/sample\"")

  expect(
    integration.send(:requires_source_file?, "spec/sample_spec.rb", "/tmp/project/lib/sample.rb")
  ).to eq(true)
end

it "matches a source file when the full path is present even if basename matching is stubbed away" do
  integration = described_class.new
  source_file = "/tmp/project/lib/sample.rb"
  allow(File).to receive(:read).and_return("load #{source_file}")
  allow(File).to receive(:basename).with(source_file, ".rb").and_return("other_name")

  expect(
    integration.send(:requires_source_file?, "spec/sample_spec.rb", source_file)
  ).to eq(true)
end

it "stops transitive traversal when a file has already been visited" do
  integration = described_class.new
  spec_file = File.expand_path("spec/sample_spec.rb")

  expect(
    integration.send(:requires_source_file_transitively?, spec_file, "lib/sample.rb", [spec_file])
  ).to eq(false)
end

it "records the current file before traversing its requires" do
  integration = described_class.new
  visited = []
  allow(integration).to receive(:requires_source_file?).and_return(false)
  allow(integration).to receive(:required_files).and_return([])

  integration.send(:requires_source_file_transitively?, "spec/sample_spec.rb", "lib/sample.rb", visited)

  expect(visited).to include(File.expand_path("spec/sample_spec.rb"))
end

it "uses relative candidates only for require_relative" do
  integration = described_class.new
  allow(integration).to receive(:relative_candidates).and_return(["relative.rb"])
  allow(integration).to receive(:require_candidates).and_return(["load_path.rb"])
  allow(File).to receive(:file?).with("relative.rb").and_return(true)

  expect(
    integration.send(:resolve_required_file, "spec/sample_spec.rb", "require_relative", "../sample")
  ).to eq("relative.rb")
end

it "expands relative candidates from the spec directory" do
  integration = described_class.new

  expect(
    integration.send(:relative_candidates, "spec/models/sample_spec.rb", "../support/helper")
  ).to eq(
    integration.send(:expand_candidates, "spec/models", "../support/helper")
  )
end

it "includes spec dir, project dir, and load path when resolving plain require" do
  integration = described_class.new
  allow(Dir).to receive(:pwd).and_return("/project")
  original_load_path = $LOAD_PATH.dup
  $LOAD_PATH.replace(["/ruby/lib", "/gem/lib"])

  expect(
    integration.send(:require_candidates, "spec/models/sample_spec.rb", "lib/sample")
  ).to include(
    File.expand_path("lib/sample", "spec/models"),
    File.expand_path("lib/sample", "/project"),
    File.expand_path("lib/sample", "/ruby/lib")
  )
ensure
  $LOAD_PATH.replace(original_load_path)
end
```

Keep one high-level integration example in `rspec_select_tests_spec.rb` that exercises a plain `require` through `$LOAD_PATH` rather than through the spec directory. That is the cleanest way to kill the survivor at line `355`.

**Step 2: Run test to verify the new coverage surface**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb spec/henitai/integration/rspec_select_tests_spec.rb
```

Expected: failures, if any, are isolated to file-selection helpers instead of the forked execution path.

**Step 3: Write minimal implementation**

Only patch `lib/henitai/integration.rb` if a direct helper example proves current fallback selection is wrong. Keep changes local to the helper under test.

**Step 4: Run test and mutation slice**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb spec/henitai/integration/rspec_select_tests_spec.rb
bundle exec henitai run 'Henitai::Integration::Rspec*'
```

Expected: survivors at lines `328`, `329`, `334`, `337`, `355`, and `365` move to `Killed`. `NoCoverage` at `313`, `320-323`, `369`, and `375-378` should also drop.

**Step 5: Commit**

```bash
git add spec/henitai/integration/rspec_spec.rb spec/henitai/integration/rspec_select_tests_spec.rb
git commit -m "test: tighten rspec fallback test selection"
```

### Task 4: Cover Minitest Setup, Baseline Spawn, And File Discovery

**Files:**
- Modify: `spec/henitai/integration/minitest_spec.rb`
- Test target: `lib/henitai/integration.rb:406-455`

**Step 1: Write the failing spec**

Add focused examples for:

```ruby
it "builds the minitest baseline suite command" do
  integration = described_class.new

  expect(integration.send(:suite_command, ["test/sample_test.rb"])).to eq(
    [
      "bundle", "exec", "ruby", "-I", "test",
      "-r", "henitai/minitest_simplecov",
      "-e", "ARGV.each { |f| require File.expand_path(f) }",
      "test/sample_test.rb"
    ]
  )
end

it "spawns the baseline suite with subprocess_env" do
  integration = described_class.new
  allow(Process).to receive(:spawn).and_return(4321)
  allow(integration).to receive(:wait_with_timeout).and_return(:timeout)

  integration.run_suite(["test/sample_test.rb"], timeout: 4.0)

  expect(Process).to have_received(:spawn).with(
    integration.send(:subprocess_env),
    *integration.send(:suite_command, ["test/sample_test.rb"]),
    out: kind_of(File),
    err: kind_of(File)
  )
end

it "requires config/environment.rb only when the file exists" do
  integration = described_class.new
  env_file = File.expand_path("config/environment.rb")
  allow(File).to receive(:exist?).with(env_file).and_return(true)
  expect(integration).to receive(:require).with(env_file)
  integration.send(:preload_environment)
end

it "adds the expanded test directory to load path only once" do
  integration = described_class.new
  test_dir = File.expand_path("test")
  original_load_path = $LOAD_PATH.dup
  $LOAD_PATH.replace([])

  2.times { integration.send(:setup_load_path) }

  expect($LOAD_PATH.count(test_dir)).to eq(1)
ensure
  $LOAD_PATH.replace(original_load_path)
end

it "sets PARALLEL_WORKERS and defaults RAILS_ENV to test" do
  integration = described_class.new
  allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(nil)

  expect(integration.send(:subprocess_env)).to eq(
    "RAILS_ENV" => "test",
    "PARALLEL_WORKERS" => "1"
  )
end

it "includes both *_test.rb and *_spec.rb and excludes test/system files" do
  with_temp_workspace do |dir|
    write_file(dir, "test/models/sample_test.rb", "")
    write_file(dir, "test/models/sample_spec.rb", "")
    write_file(dir, "test/system/browser_test.rb", "")

    expect(described_class.new.test_files).to match_array(
      ["test/models/sample_test.rb", "test/models/sample_spec.rb"]
    )
  end
end
```

**Step 2: Run test to verify the new coverage surface**

Run:

```bash
bundle exec rspec spec/henitai/integration/minitest_spec.rb
```

Expected: failures, if any, stay local to the Minitest adapter helpers.

**Step 3: Write minimal implementation**

Patch `lib/henitai/integration.rb` only if the new examples expose a real defect in `Minitest` setup behavior.

**Step 4: Run test and mutation slice**

Run:

```bash
bundle exec rspec spec/henitai/integration/minitest_spec.rb
bundle exec henitai run 'Henitai::Integration::Minitest*'
```

Expected: survivors at lines `441`, `442`, and `453` move to `Killed`. `NoCoverage` at `406-421` and `447-448` should disappear.

**Step 5: Commit**

```bash
git add spec/henitai/integration/minitest_spec.rb
git commit -m "test: cover minitest integration helpers"
```

### Task 5: Final Verification And Cleanup

**Files:**
- Verify: `spec/henitai/integration/scenario_log_support_spec.rb`
- Verify: `spec/henitai/integration/rspec_spec.rb`
- Verify: `spec/henitai/integration/rspec_select_tests_spec.rb`
- Verify: `spec/henitai/integration/minitest_spec.rb`

**Step 1: Run the focused integration specs**

```bash
bundle exec rspec \
  spec/henitai/integration/scenario_log_support_spec.rb \
  spec/henitai/integration/rspec_spec.rb \
  spec/henitai/integration/rspec_select_tests_spec.rb \
  spec/henitai/integration/minitest_spec.rb
```

Expected: PASS

**Step 2: Run the full suite**

```bash
bundle exec rspec
```

Expected: PASS

**Step 3: Run the targeted mutation slice**

```bash
bundle exec henitai run 'Henitai::Integration*'
```

Expected: the surviving set for `lib/henitai/integration.rb` is materially smaller, and the previously uncovered helper seams are now covered.

**Step 4: Check the report**

Open `reports/mutation-report.json` and confirm the old survivor lines are no longer listed as `Survived`.

**Step 5: Commit**

```bash
git add spec/henitai/integration/scenario_log_support_spec.rb \
  spec/henitai/integration/rspec_spec.rb \
  spec/henitai/integration/rspec_select_tests_spec.rb \
  spec/henitai/integration/minitest_spec.rb
git commit -m "test: increase integration adapter mutation coverage"
```

## Notes

- Avoid using the existing fork-heavy mutant execution path to test helper seams that can be exercised directly. Several `Timeout` mutations sit in `ScenarioLogSupport`; direct helper specs are the safer route.
- Keep private-helper testing pragmatic here. These helpers are where the mutation report is pointing, and there is no cleaner public seam for several of them yet.
- Do not update public docs unless the implementation uncovers and changes an actual runtime contract.
