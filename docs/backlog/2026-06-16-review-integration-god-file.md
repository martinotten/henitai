# Decompose integration.rb God File

Status: backlog
Date: 2026-06-16
Severity: High
Source: 2026-06-16 structured review

## Summary

`lib/henitai/integration.rb` is a 953-line file holding nine distinct types and
several duplicated methods. It is the largest and least cohesive file in the
codebase, and it blurs the boundary between framework adaptation and domain
logic that the architecture docs claim to enforce.

## Problem

- `lib/henitai/integration.rb` is 953 lines with `# rubocop:disable
  Metrics/ModuleLength` (line 116).
- `ScenarioLogSupport` is defined twice in the same namespace: line 24
  (`capture_child_output`, IO redirect) and line 760 (`read_log_file`,
  `write_combined_log`). Ruby reopens the class, so its methods are scattered
  736 lines apart — confusing and easy to break.
- `suppress_simplecov!` appears at lines 198, 727, 790, and 899 across
  `CoverageRuntimeSuppressors` and `Integration::Minitest`. The Minitest copy
  (line 899) duplicates the `CoverageRuntimeSuppressors` version verbatim.
- `ChildDebugSupport` (line 116) holds RSpec-specific methods
  (`run_rspec_runner`, `build_rspec_runner`, `configure_rspec_runner`,
  `load_rspec_spec_files`) yet is mixed into the shared `Base` (line 330),
  contaminating every integration including Minitest.

This file has no direct spec; it is covered only indirectly through
`spec/henitai/integration/*`.

## Fix Plan

TDD throughout. Run `bundle exec rspec spec/henitai/integration` after each step;
keep green.

1. **Characterize first.** Add a focused spec for the `Base` public surface
   (`spawn_mutant`, `build_result`, log capture) before moving any code. This
   locks current behavior.
2. **Extract log support.** Pull both `ScenarioLogSupport` bodies into a single
   `lib/henitai/integration/scenario_log_support.rb` class. Merge the two method
   sets; delete the duplicate definition. Add a dedicated spec.
3. **Extract coverage suppression.** Move `CoverageRuntimeSuppressors`,
   `SimpleCovStartSuppressor`, `CoverageStartSuppressor` into
   `lib/henitai/integration/coverage_suppression.rb`. Delete the verbatim
   `suppress_simplecov!`/`suppress_coverage!` copies in `Integration::Minitest`;
   call the shared module instead.
4. **Split RSpec specifics.** Move `ChildDebugSupport`'s RSpec methods into the
   `Rspec` class (or a `RspecRunnerSupport` mixin included only by `Rspec`), out
   of `Base`. See sibling issue on `Minitest < Rspec`.
5. **Re-home `Base`.** Leave only the framework-agnostic `Base` in
   `integration.rb` (or `integration/base.rb`). Update `lib/henitai/integration.rb`
   to require the new files.
6. Drop the `Metrics/ModuleLength` disable once under 200 lines.

## Acceptance

- No file in `lib/henitai/integration*` exceeds 200 lines.
- `ScenarioLogSupport` and `suppress_simplecov!` each defined exactly once.
- No RSpec method reachable on a Minitest integration instance.
- `bundle exec rspec` and `bundle exec rubocop` green with no new disables.

## Related

- [[2026-06-16-review-minitest-inherits-rspec]]
- [[2026-06-16-review-class-size-discipline]]
