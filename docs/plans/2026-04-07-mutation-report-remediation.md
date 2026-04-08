# Mutation Report Remediation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Raise the mutation score by closing the current survivor and no-coverage hotspots in the latest report.

**Architecture:** Keep the fixes narrow and test-driven. Start with the highest-leverage pure functions and serialization paths, then move to orchestration helpers, then tackle the larger timeout hotspots by extracting smaller seams where needed. Reuse the existing `integration.rb` and static-filter follow-up plans instead of duplicating that work here.

**Tech Stack:** Ruby 4.0.2, RSpec, SimpleCov resultset JSON, Henitai mutation report

---

## 1. Report Triage

Latest report snapshot:

- `Survived`: 55
- `NoCoverage`: 24
- `Timeout`: 37
- `CompileError`: 58

Highest-value files by remaining non-killed mutants:

- `lib/henitai/reporter.rb` - 34
- `lib/henitai/configuration_validator.rb` - 29
- `lib/henitai/integration.rb` - 24
- `lib/henitai/cli.rb` - 23
- `lib/henitai/result.rb` - 9
- `lib/henitai/mutant/activator.rb` - 8
- `lib/henitai/subject_resolver.rb` - 7
- `lib/henitai/mutant_history_store.rb` - 6
- `lib/henitai/coverage_bootstrapper.rb` - 5
- `lib/henitai/execution_engine.rb` - 5
- `lib/henitai/runner.rb` - 4
- `lib/henitai/scenario_execution_result.rb` - 4
- `lib/henitai/static_filter.rb` - 2
- `lib/henitai/equivalence_detector.rb` - 2
- `lib/henitai/arid_node_filter.rb` - 1
- `lib/henitai/configuration.rb` - 1
- `lib/henitai/operators/string_literal.rb` - 1
- `lib/henitai/warning_silencer.rb` - 1

Priority rule:

1. Kill `Survived` mutants first.
2. Close `NoCoverage` gaps that sit on the same helper seams.
3. Only then spend time on `Timeout` and `CompileError` mutants, because those are usually a signal that the code needs smaller seams, not broader end-to-end specs.

Existing plan files to reuse:

- `docs/plans/2026-04-04-integration-rb-coverage.md`
- `docs/plans/2026-04-07-coverage-blind-spots.md`
- `docs/plans/2026-04-07-method-coverage-static-filter.md`

---

## 2. Task Breakdown

### Task 1: Pin `Result` Serialization And Scoring

**Files:**
- Modify: `spec/henitai/result_spec.rb`
- Modify: `spec/henitai/reporter/json_spec.rb`

**Why this first:** `lib/henitai/result.rb` has 9 surviving mutants, all on status serialization strings. This is low-risk, high-leverage coverage.

**Step 1: Write the failing test**

Add a spec that builds a result with one mutant of each status and asserts the serialized Stryker schema contains the exact status mappings, including `Ignored` for `:equivalent`, `NoCoverage`, `CompileError`, and `RuntimeError`.

Add a second spec that asserts `mutation_score` excludes `:ignored`, `:no_coverage`, `:compile_error`, and `:equivalent` from the denominator.

**Step 2: Run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/result_spec.rb
```

Expected: the new exact-mapping example fails before the implementation change.

**Step 3: Implement the smallest change**

If the new example fails, keep the implementation local to `Result#stryker_status` or the scoring helpers. Do not broaden the public API.

**Step 4: Re-run the spec**

Run:

```bash
bundle exec rspec spec/henitai/result_spec.rb
```

Expected: pass.

**Step 5: Check the mutation slice**

Run:

```bash
bundle exec henitai run 'Henitai::Result'
```

Expected: the 9 surviving string-literal mutants in `lib/henitai/result.rb` disappear.

---

### Task 2: Tighten Configuration Validation Messages

**Files:**
- Modify: `spec/henitai/configuration_validator_spec.rb`
- Modify: `spec/henitai/configuration_spec.rb`

**Why this next:** `lib/henitai/configuration_validator.rb` has a mix of survivors and compile-error mutants. The survivors are mostly string-literal interpolation paths, which are best pinned with exact error messages.

**Step 1: Write the failing test**

Replace loose regex expectations with exact message expectations for these paths:

- `mutation.ignore_patterns`
- `mutation.max_mutants_per_line`
- `mutation.max_flaky_retries`
- `mutation.sampling.ratio`
- `mutation.sampling.strategy`

Also add one direct spec for the root configuration type check so the error text stays stable.

**Step 2: Run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/configuration_validator_spec.rb spec/henitai/configuration_spec.rb
```

Expected: at least one of the new exact-message examples fails before implementation.

**Step 3: Implement the smallest change**

If any failure is due to a missing or inaccurate error message, adjust only the relevant validator helper.

**Step 4: Re-run the spec**

Run:

```bash
bundle exec rspec spec/henitai/configuration_validator_spec.rb spec/henitai/configuration_spec.rb
```

Expected: pass.

**Step 5: Check the mutation slice**

Run:

```bash
bundle exec henitai run 'Henitai::ConfigurationValidator*'
```

Expected: the 6 surviving configuration-validator string mutants are killed. Leave the compile-error mutants for later unless they disappear naturally after helper extraction.

---

### Task 3: Cover History, Subject Resolution, And Mutant Activation Helpers

**Files:**
- Modify: `spec/henitai/mutant_history_store_spec.rb`
- Modify: `spec/henitai/subject_resolver_spec.rb`
- Modify: `spec/henitai/mutant/activator_spec.rb`
- Modify: `spec/henitai/arid_node_filter_spec.rb`
- Modify: `spec/henitai/equivalence_detector_spec.rb`

**Why this cluster:** These files hold smaller helper-level survivors. They should be fixed with direct helper specs, not broader integration tests.

**Step 1: Write the failing tests**

Add focused examples for:

- `MutantHistoryStore`:
  - exact `load_runs`/`load_mutants` field names
  - `mutation_signature` fallback when `Unparser` fails
  - status-history persistence for repeated runs
- `SubjectResolver`:
  - root-qualified constant names
  - `define_method` detection with `self` and bare receivers
  - anonymous class/module/struct/data handling
- `Mutant::Activator`:
  - `prefixed_parameter` with and without a parameter name
  - `source_file_from_ast` when source metadata is inferred
  - `load_source_file` behavior when the target file exists
- `AridNodeFilter`:
  - Rails logger receiver detection with a non-Rails constant receiver
  - `send_call?` behavior for malformed send nodes
- `EquivalenceDetector`:
  - additive and multiplicative neutral-operand detection for the exact helper shapes

**Step 2: Run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/mutant_history_store_spec.rb spec/henitai/subject_resolver_spec.rb spec/henitai/mutant/activator_spec.rb spec/henitai/arid_node_filter_spec.rb spec/henitai/equivalence_detector_spec.rb
```

Expected: one or more of the new helper-level examples fail before implementation.

**Step 3: Implement the smallest change**

Keep the changes local to the helper method that the new example exercises.

**Step 4: Re-run the specs**

Run the same `bundle exec rspec ...` command again.

Expected: pass.

**Step 5: Check the mutation slices**

Run:

```bash
bundle exec henitai run 'Henitai::MutantHistoryStore'
bundle exec henitai run 'Henitai::SubjectResolver'
bundle exec henitai run 'Henitai::Mutant::Activator'
bundle exec henitai run 'Henitai::AridNodeFilter'
bundle exec henitai run 'Henitai::EquivalenceDetector'
```

Expected: the remaining survivors in these helper-heavy files disappear or shrink to true compile-time artifacts.

---

### Task 4: Close Orchestration NoCoverage Gaps

**Files:**
- Modify: `spec/henitai/coverage_bootstrapper_spec.rb`
- Modify: `spec/henitai/runner_spec.rb`
- Modify: `spec/henitai/scenario_execution_result_spec.rb`
- Modify: `spec/henitai/static_filter_spec.rb`
- Modify: `spec/henitai/execution_engine_spec.rb`

**Why this cluster:** These files hold the remaining `NoCoverage` and a few survivor/timeout seams that are cheap to close with direct, small tests.

**Step 1: Write the failing tests**

Add examples for:

- `CoverageBootstrapper#coverage_dir` fallback when `reports_dir` is nil or empty
- `Runner#progress_reporter` returning `nil` when the terminal reporter is disabled
- `Runner#history_store` path construction from `reports_dir`
- `ScenarioExecutionResult#combined_output` and `#failure_tail`
- `StaticFilter#coverage_lines_for` behavior when the coverage report exists but has no usable lines
- `ExecutionEngine#worker_count` fallback to `Etc.nprocessors`
- `ExecutionEngine#warn_flaky_mutants` staying quiet under the threshold

**Step 2: Run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/coverage_bootstrapper_spec.rb spec/henitai/runner_spec.rb spec/henitai/scenario_execution_result_spec.rb spec/henitai/static_filter_spec.rb spec/henitai/execution_engine_spec.rb
```

Expected: at least one of the new boundary examples fails before implementation.

**Step 3: Implement the smallest change**

Only touch the helper that the new example characterizes.

**Step 4: Re-run the specs**

Run the same `bundle exec rspec ...` command again.

Expected: pass.

**Step 5: Check the mutation slices**

Run:

```bash
bundle exec henitai run 'Henitai::CoverageBootstrapper'
bundle exec henitai run 'Henitai::Runner'
bundle exec henitai run 'Henitai::ScenarioExecutionResult'
bundle exec henitai run 'Henitai::StaticFilter'
bundle exec henitai run 'Henitai::ExecutionEngine'
```

Expected: the current `NoCoverage` pockets shrink and the remaining survivors in these helpers are eliminated where they are real behavior, not syntax artifacts.

---

### Task 5: Break Up CLI And Reporter Hotspots

**Files:**
- Modify: `spec/henitai/cli_spec.rb`
- Modify: `spec/henitai/reporter/terminal_spec.rb`
- Modify: `spec/henitai/reporter/html_spec.rb`
- Create: `spec/henitai/reporter_spec.rb` if module-level coverage is still missing

**Why this last:** `lib/henitai/cli.rb` and `lib/henitai/reporter.rb` hold the most `Timeout` mutants. These are usually a sign that the code needs smaller seams, not more broad end-to-end specs.

**Step 1: Write the failing tests**

Add exact-output specs for the helper seams that are already public or easy to expose via `send`:

- `CLI#help_text`
- `CLI#operator_help_text`
- `CLI#integration_block`
- `CLI#exit_status_for`
- `CLI#subjects_from_argv`
- `Reporter.reporter_class`
- `Reporter::Base#report`
- `Reporter::Terminal#summary_lines`
- `Reporter::Terminal#progress`
- `Reporter::Html#html_document`

Prefer direct unit tests over `cli.run` or full reporter integration tests when the mutation report shows timeouts. The goal is to give each helper a fast, isolated spec that finishes well under the mutation timeout budget.

**Step 2: Run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/cli_spec.rb spec/henitai/reporter/terminal_spec.rb spec/henitai/reporter/html_spec.rb
```

If `spec/henitai/reporter_spec.rb` is added, include it in the same command.

Expected: the new helper examples fail before any implementation extraction.

**Step 3: Extract only if needed**

If the direct spec still produces timeouts, extract the helper into a smaller pure method or a small value object. Do not expand the public API unless the extraction makes the code easier to test and easier to read.

**Step 4: Re-run the specs**

Run the same `bundle exec rspec ...` command again.

Expected: pass.

**Step 5: Check the mutation slices**

Run:

```bash
bundle exec henitai run 'Henitai::CLI'
bundle exec henitai run 'Henitai::Reporter*'
```

Expected: the timeout-heavy mutants either die or are reduced to a small set of true compile-time artifacts.

---

### Task 6: Re-run The Report And Decide On Remaining Compile Errors

**Files:**
- No code change first

**Why this is separate:** `CompileError` mutants are not always fixable with tests. Some are genuine structural artifacts of the mutation operator, so they should be re-evaluated only after the survivor and no-coverage cleanup is done.

**Step 1: Run the full test suite**

Run:

```bash
bundle exec rspec
```

Expected: green.

**Step 2: Run the full mutation suite**

Run:

```bash
bundle exec henitai run
```

Expected: the survivors and no-coverage counts drop materially from the current report. Any remaining compile errors should be reviewed file-by-file to decide whether they are:

- acceptable equivalent/syntax artifacts
- a sign that a helper should be extracted
- a real regression that needs another direct spec

**Step 3: Update the docs if behavior changed**

If any public behavior changed while fixing these mutants, update the relevant README or architecture notes before closing the work.

