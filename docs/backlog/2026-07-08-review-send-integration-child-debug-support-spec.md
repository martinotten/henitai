# `integration/child_debug_support_spec` Uses `send` to Reach Private Debug Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/integration/child_debug_support_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/integration/child_debug_support_spec.rb)
reaches into private helper methods with `send`, including debug-child
inspection and example-count helpers.

## Problem

- The spec is coupled to helper names and signatures instead of observable
  behavior.
- Refactors inside the support module will force test churn.

## Fix Sketch

- Cover the debug behavior through the public integration path that consumes
  the support module.
- Keep helper-level tests only where a public seam exists.

## Test Plan

- Remove `send` calls from the support spec.
- Add behavior-level assertions around the integration entry point.

## Convention Note (added 2026-08-21)

The Fix Sketch above says to shift coverage to the public entry points. That
prescription is **superseded**: see
[`2026-07-08-review-send-integration-minitest-spec.md`](2026-07-08-review-send-integration-minitest-spec.md),
the one ticket in this family that was actually resolved. It extracted public
collaborators instead, and took `Henitai::Integration::Minitest` from
MS 72.83% / MSI 43.05% to MS 100% / MSI 91.87%.

This repository scores mutation coverage against itself, so a pure public-API
rewrite usually *loses* coverage — the assertions end up further from the logic
they constrain. Extract a public collaborator; rewrite in place only where a
public path genuinely reaches the behavior.

The budget for this file in `spec/infra/private_method_reach_spec.rb` must come
down in the same commit as any reduction here.

## Resolution (2026-08-21)

`Integration::ChildDebugSupport` is deleted. Its 33 `send` calls are gone, and
the budget entry was removed from the private-reach ratchet in the same commit.
It became two public classes:

- **`Integration::ChildDebugLog`** (`lib/henitai/integration/child_debug_log.rb`)
  — `#enabled?`, `#write`, `#rspec_trace`, `#rspec_exit`, `#example_count`,
  `#activation_start`, `#activation_end`, `#mutant_meta`, `#activation_check`,
  `#timeout_signal_sent`, `#thread_dump`, `#rspec_world_example_count`.
- **`Integration::LoadedFeatures`** (`lib/henitai/integration/loaded_features.rb`)
  — `#include?` (was `loaded_feature?`, 9 of the 33 sends) and `#map`, injected
  into `ChildDebugLog` so the "`#inspect`, not `#to_s`" assertion still has a
  seam to work through.

`Integration::Base` exposes a public memoized `#child_debug_log`; every call
site in `integration.rb`, `rspec_child_runner.rb`, `mutant_run_support.rb` and
`child_runtime_control.rb` now goes through it.

### Deviations from the plan, and why

- **`#timeout_dump` did not move into the log.** It sends `SIGUSR1`, sleeps, and
  rescues `Errno::ESRCH` — signalling, not logging. `ChildRuntimeControl` keeps
  it and now reads `child_debug_log.enabled?`; the log only gained a
  `#timeout_signal_sent(pid)` line. `#thread_dump`, which is pure logging, did
  move.
- **`io:` is resolved per call, never memoized.**
  `ScenarioLogSupport#capture_child_output` reassigns `$stdout` inside the child
  *after* `Base` memoizes the log, so an `io: $stdout` default captured at
  construction sends every debug line to the parent's terminal instead of the
  child's log file. Neither the unit suite nor the smoke suite covers the debug
  path, so this was verified by hand with `HENITAI_DEBUG_CHILD=1`.
- **Redundant `if debug_child?` call-site guards were dropped** from
  `mutant_run_support.rb`; each log method gates internally.

### Coverage that had to be repaired, not just relocated

Falsifying the ported examples (breaking the implementation on purpose and
confirming the spec goes red) showed four of them proved nothing:

1. `#write` reading `$stdout` late — `output(...).to_stdout` swaps the global
   before the block runs, so it passed even with the stream captured at
   construction. Replaced with an explicit two-stream example that asserts the
   pre-redirect stream stayed empty.
2. `#mutant_meta` / `#activation_check` early returns — `#write` gates
   internally, so an output-only assertion passed with the guard deleted. Now
   asserted as *no work done*: the mutant is never interrogated, `Runner` is
   never reflected on.
3. `#rspec_trace`, `#example_count`, `#thread_dump` got the same treatment
   (`LoadedFeatures#map`, `RSpec.world`, `Thread.list` are never called when
   disabled).
4. `LoadedFeatures#normalize`'s `rescue StandardError` — the ported example used
   a feature string that matched raw, so `||` short-circuited and `#normalize`
   never ran. It passed with the rescue deleted. Rewritten with a feature that
   matches nothing, asserting `#include?` returns `false` instead of raising.

### RBS

Both `ChildDebugSupport` declaration blocks are gone (the module block and the
re-declaration on `Integration::Base`), replaced by `ChildDebugLog` and
`LoadedFeatures` class declarations plus `Base#child_debug_log`. All **seven**
`# steep:ignore` comments that existed only because Steep could not see
mixin-provided methods (five in `child_debug_support.rb`, two in
`integration.rb`) are gone; `steep check` is clean without them. That was the
acceptance signal for the extraction being complete rather than laundered.
