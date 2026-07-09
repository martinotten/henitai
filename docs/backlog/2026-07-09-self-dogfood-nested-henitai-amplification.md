# Self-Dogfood Runs Amplify Processes via Specs That Re-Launch henitai

Status: implemented (2026-07-09, config-level mitigation; deeper guard left open)
Date: 2026-07-09
Severity: Medium
Source: observed while investigating a long-running dogfood run — a single
mutant child's captured log contained henitai CLI help text, `operator list`
output, `partial rerun` lines, nested `333 examples` RSpec runs and
`SimpleCov failed to recognize the test framework` warnings, and the process
list grew far beyond `jobs` concurrent workers.

## Summary

henitai runs each mutant in a forked child that executes the specs covering
the mutated subject (`ExecutionEngine#prioritized_tests_for` →
`integration.select_tests`). When henitai is mutation-tested **on itself**,
some of those specs drive henitai end-to-end and spawn their own subprocesses:

- `spec/henitai/cli_spec.rb` runs the real `Henitai::CLI` (`run` / `operator`
  / etc.) → full pipeline → `ExecutionEngine` forks mutant children.
- `spec/henitai/{process_worker_runner,slot_scheduler}_spec.rb` and
  `spec/henitai/integration/{rspec,rspec_process_runner,child_debug_support}_spec.rb`
  fork real child processes.

Because these integration-style specs exercise most of `lib/`, per-test
coverage selects them for the majority of subjects. So a large fraction of
mutant children each re-launch a nested henitai/CLI process tree — which may
fork again — multiplying live processes well past `jobs`, inflating wall-clock,
and filling the captured logs with nested-run noise (the CLI help / SimpleCov
lines above). This is also what fed the runaway-output problem addressed
separately by the child-output cap.

## Impact

- Process count balloons far beyond the configured `jobs` on self-dogfood runs;
  combined with hard-kills this compounds the orphaned-worker leak
  (`2026-07-09-orphaned-worker-processes-on-parent-kill.md`).
- Wall-clock inflated by redundant nested henitai runs per mutant.
- Captured mutant logs polluted with unrelated nested-run output, obscuring the
  real failure that killed (or failed to kill) the mutant.

## Fix (implemented)

Added a `test_excludes` configuration key: an array of globs; matching spec
files are dropped from per-mutant test selection
(`ExecutionEngine#reject_excluded_tests`, applied before per-test coverage
filtering and prioritisation). Set in this repo's `.henitai.yml` to exclude the
CLI and process-forking specs above, keeping the fork tree flat.

- Config: `Configuration#test_excludes` (default `[]`), validated as a string
  array, documented in `assets/schema/henitai.schema.json` and RBS.
- Filter matches on `File.expand_path` + `File.fnmatch?(…, File::FNM_PATHNAME)`
  so a `*` glob does not cross directory boundaries.
- **Trade-off:** mutants in the CLI / execution-scheduler subsystem lose the
  coverage those excluded specs provided during dogfood runs — some may report
  `NoCoverage`/`Survived` that a full run would kill. Acceptable for dogfooding
  (those subsystems are integration-heavy and awkward to mutation-test in-process
  anyway); `test_excludes` is opt-in and empty by default, so other projects are
  unaffected.

## Deeper hardening (still open)

`test_excludes` is a per-repo mitigation, not a structural guard. Each forked
mutant child already exports `HENITAI_MUTANT_ID` (`rspec_process_runner.rb`).
A nested henitai invocation could detect it (or a dedicated nesting-depth env)
and refuse to start a real mutation run / real forks — capping recursion depth
regardless of which specs are selected. That is more invasive (must not break
the specs that legitimately test forking) and is deferred; `test_excludes`
covers the practical need now.

## Test Plan

- Unit: `ExecutionEngine#reject_excluded_tests` drops matching globs, keeps the
  rest, and respects `FNM_PATHNAME` (glob does not cross `/`). ✅
- Config: `test_excludes` loads, defaults to `[]`, rejects a non-array. ✅
- Schema: `test_excludes` documented; sample `.henitai.yml` stays within the
  documented top-level keys. ✅
- Regression: full suite + `rake smoke:integration:all` green (empty
  `test_excludes` in the fixture projects → unchanged selection). ✅
