# Reduce Over-Mocking and Close Spec Coverage Gaps

Status: backlog
Date: 2026-06-16
Severity: High
Source: 2026-06-16 structured review

## Summary

For a mutation-testing tool, test quality is the product. Two problems undercut
that: the main pipeline spec over-mocks and asserts on call ordering, and eleven
lib files have no direct spec — including non-trivial signal handling.

## Problem

- `spec/henitai/runner_spec.rb` is 1191 lines with ~227 `allow`/`instance_double`
  calls. The pipeline example builds 8 `instance_double`s, stubs every
  collaborator, then asserts on a call-ordering event log. This couples the test
  to implementation; any internal refactor breaks it without a behavioral
  regression — exactly the brittleness mutation testing exists to expose.
- Lib files with no direct spec:
  `eager_load.rb`, `integration.rb` (953 lines), `minitest_coverage_hook.rb`,
  `minitest_simplecov.rb`, `parser_current.rb`, `process_wakeup.rb` (signal/pipe
  handling), `reporter.rb` (517 lines), `rspec_coverage_formatter.rb`,
  `unparse_helper.rb`, `version.rb`, `warning_silencer.rb`.
  `integration.rb` and `reporter.rb` are partially covered indirectly; the
  others are not.

## Fix Plan

1. **`process_wakeup.rb` first** (highest risk, zero coverage). Spec the pipe
   install/drain/close lifecycle and signal-handler restoration with a fake
   IO/trap seam. Bugs here corrupt child reaping in parallel runs.
2. **Rework `runner_spec.rb`.** Replace the call-ordering event-log assertions
   with behavioral assertions on observable outputs (the produced `Result`,
   reported counts, exit status). Keep doubles only at true infrastructure
   seams (process spawning, filesystem). Target: drop stub count substantially,
   assert on outcomes not sequence.
3. **Cover the small loaders/helpers** (`unparse_helper`, `warning_silencer`,
   `rspec_coverage_formatter`, `minitest_*`) with focused specs — these are
   small and quick wins.
4. **`reporter.rb` / `integration.rb`:** add direct specs as part of their
   decomposition tickets, not separately.
5. **Guard the gap.** Dogfood (see lenient-config ticket) plus a CI check that
   flags new lib files lacking a spec.

## Acceptance

- `process_wakeup.rb` has a dedicated spec.
- `runner_spec.rb` asserts behavior, not internal call order; stub count
  materially reduced.
- All trivial loader/helper files have specs.

## Related

- [[2026-06-16-review-flaky-timing-specs]]
- [[2026-06-16-review-lenient-dogfood-config]]
- [[2026-06-16-review-integration-god-file]]
