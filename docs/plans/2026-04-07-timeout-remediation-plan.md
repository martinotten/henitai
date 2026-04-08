# Timeout Remediation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate false timeout classifications during mutant execution and reduce avoidable runtime overhead in the integration path.

**Architecture:** Keep timeout enforcement inside the integration adapter, but make the deadline check race-resistant so a child that exits right at the boundary is still reaped before being marked as timed out. Reduce per-mutant filesystem work by avoiding unnecessary combined-log writes, and prune stale mutation logs so the reports directory does not become a performance sink. Preserve the public output contract for reporters and existing log paths.

**Tech Stack:** Ruby 4.0.x, RSpec, Process fork/wait, filesystem logging

---

## 1. Diagnosis Summary

Recent runs show a mutant finishing at roughly `9.9s` while the configured timeout is `10.0s`. That leaves almost no slack for fork scheduling, polling granularity, log flushing, and process reaping. The workspace also contains a very large `reports/mutation-logs` directory, which adds filesystem overhead and makes log handling more expensive than intended.

---

## 2. Task Breakdown

### Task 1: Make Deadline Handling Race-Resistant

**Files:**
- Modify: `lib/henitai/integration.rb`
- Modify: `spec/henitai/integration/rspec_spec.rb`

**Step 1: Write the failing test**

Add a spec that simulates a child process exiting immediately before the deadline but after the last polling iteration. The expectation should be that `wait_with_timeout` returns the child status, not `:timeout`.

**Step 2: Run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb
```

Expected: the new boundary example fails before implementation.

**Step 3: Implement the minimal fix**

Refine `wait_with_timeout` so it performs one final non-blocking `Process.wait(pid, Process::WNOHANG)` check before calling `handle_timeout`. Keep the existing timeout semantics and child-kill behavior otherwise unchanged.

**Step 4: Re-run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb
```

Expected: pass.

---

### Task 2: Remove Unnecessary Combined-Log Writes

**Files:**
- Modify: `lib/henitai/integration.rb`
- Modify: `lib/henitai/scenario_execution_result.rb`
- Modify: `spec/henitai/integration/rspec_spec.rb`
- Modify: `spec/henitai/scenario_execution_result_spec.rb`

**Step 1: Write the failing test**

Add a spec that proves `ScenarioExecutionResult#log_text` can still reconstruct output from `stdout` and `stderr` when the combined log file does not exist. Add a second spec that exercises the integration result path without requiring `write_combined_log` to run for every mutant.

**Step 2: Run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/scenario_execution_result_spec.rb spec/henitai/integration/rspec_spec.rb
```

Expected: at least one new example fails before implementation.

**Step 3: Implement the smallest change**

Prefer lazy log synthesis in `ScenarioExecutionResult#log_text` and keep `build_result` focused on capturing `stdout`, `stderr`, and status. Only write a combined log file when the existing reporter contract truly needs a persisted artifact.

**Step 4: Re-run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/scenario_execution_result_spec.rb spec/henitai/integration/rspec_spec.rb
```

Expected: pass.

---

### Task 3: Prune Stale Mutation Logs Before a Run

**Files:**
- Modify: `lib/henitai/execution_engine.rb`
- Modify: `spec/henitai/execution_engine_spec.rb`

**Step 1: Write the failing test**

Add a spec that verifies the engine clears or rotates `reports/mutation-logs` at the start of a run, so one run does not pay the cost of an ever-growing directory tree from previous runs.

**Step 2: Run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/execution_engine_spec.rb
```

Expected: the new cleanup example fails before implementation.

**Step 3: Implement the smallest change**

Add a narrow cleanup helper that removes stale files from the current run’s mutation-log directory before mutant execution begins. Keep the behavior scoped to the configured `reports_dir` and avoid touching unrelated report artifacts.

**Step 4: Re-run the focused spec**

Run:

```bash
bundle exec rspec spec/henitai/execution_engine_spec.rb
```

Expected: pass.

---

### Task 4: Recalibrate the Default Timeout Only If Needed

**Files:**
- Modify: `lib/henitai/configuration.rb`
- Modify: `README.md`
- Modify: `docs/architecture/architecture.md`

**Step 1: Validate with a targeted mutation run**

Run a focused mutation slice for the integration path after Tasks 1-3 land:

```bash
bundle exec henitai run 'Henitai::Integration::Rspec'
```

Expected: the false timeout disappears or drops materially.

**Step 2: Decide on the default**

If the run still times out at the boundary, raise the default mutation timeout by a small amount and document the rationale. If the run is clean after the race fix and log pruning, keep the default unchanged.

**Step 3: Update docs if the default changes**

Document the new default in `README.md` and the architecture/configuration references so the public contract stays accurate.

---

### Task 5: Verify The Fix End-to-End

**Files:**
- No new code first

**Step 1: Run the focused specs**

Run:

```bash
bundle exec rspec spec/henitai/integration/rspec_spec.rb spec/henitai/scenario_execution_result_spec.rb spec/henitai/execution_engine_spec.rb
```

Expected: pass.

**Step 2: Run the full test suite**

Run:

```bash
bundle exec rspec
```

Expected: green.

**Step 3: Re-run the mutation slice**

Run:

```bash
bundle exec henitai run 'Henitai::Integration::Rspec'
bundle exec henitai run 'Henitai::ExecutionEngine'
```

Expected: the timeout-count drops and the remaining issues, if any, are true behavior gaps rather than deadline races.

