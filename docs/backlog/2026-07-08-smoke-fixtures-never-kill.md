# Smoke-Fixture Mutants Are Never Killed (Activation Clobbered by Spec Require)

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered while wiring an end-to-end incremental-cache assertion
into the smoke rake tasks (`2026-07-06-incremental-verdict-cache.md`)

## Summary

Every mutant in both integration smoke projects
(`spec/fixtures/integration_smoke/{rspec,minitest}`) reports `Survived` or
`Ignored` — never `Killed` — even for mutations that must fail the fixture
suite (e.g. `ReturnValue` replacing `Greeting#message` with `nil` while a
spec asserts `be_truthy`, or `ArithmeticOperator` mutating
`double(input) = input * 2` while a spec asserts `double(3) == 6`).
Child logs confirm the suite passes untouched (`6 examples, 0 failures`)
with the mutant supposedly active.

## Root Cause (verified against the code path, not yet fix-tested)

`Mutant::Activator#load_source_file` loads the subject's file via `load`
(`lib/henitai/mutant/activator.rb`), which does **not** register the file in
`$LOADED_FEATURES`. In the forked child, activation runs **before** the spec
files are loaded (`run_child_activation_and_tests` in
`lib/henitai/integration/mutant_run_support.rb` → `run_tests` →
`load_rspec_spec_files`). The fixture specs begin with
`require_relative "../lib/greeting"`; since the file was only ever `load`ed,
`require_relative` loads the original source again and **redefines the
mutated method back to the original**. Every mutant therefore runs against
unmutated code and survives.

The dogfood path doesn't hit this because henitai's own lib is fully
`require`d in the parent before fork, so the child's `$LOADED_FEATURES`
already contains every subject file and the specs' requires are no-ops.

## Impact

- Both smoke projects silently exercise only the survive/ignore paths; the
  kill path has zero end-to-end coverage.
- The incremental-verdict-cache smoke assertion (double run, expect
  `fromCache`) cannot work against these fixtures and was dropped —
  restore it once this is fixed (see the incremental ticket's notes).

## Fix Sketch

- After `load(source_file)` in the activator, append the expanded path to
  `$LOADED_FEATURES` so subsequent `require`/`require_relative` of the
  subject file are no-ops; or
- Activate the mutant **after** loading the spec files (order flip in
  `run_child_activation_and_tests` — needs care: activation must still
  precede test *execution*).
- Either way: extend the smoke rake verification with a
  `killed_count.positive?` assertion so this regression class stays caught,
  and re-add the incremental double-run assertion.

## Test Plan

- Smoke: both fixtures report ≥1 `Killed` mutant (`double` mutants).
- Unit: activator spec proving a `require_relative` of the subject file
  after activation does not restore the original method.
- Regression: dogfood run unchanged.
