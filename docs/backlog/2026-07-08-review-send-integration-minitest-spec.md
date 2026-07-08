# `integration/minitest_spec` Uses `send` to Reach Private Integration Helpers

Status: done (2026-07-09)
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/integration/minitest_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/integration/minitest_spec.rb)
calls a large number of private helper methods via `send`, covering command
construction, environment setup, test execution, and cleanup internals.

## Problem

- The spec is tightly coupled to the implementation shape of the adapter.
- Helper renames or internal extraction will create noisy failures.

## Fix Sketch

- Shift the important coverage to the public integration entry points.
- Keep only the smallest number of private-helper tests if a public seam truly
  does not exist.

## Test Plan

- Remove the broad `send`-based helper coverage where a public behavior test can
  cover the same contract.
- Add focused behavior specs for the user-visible adapter outcomes.

## Resolution (2026-07-09)

Extracted the private helpers into public-API collaborators — `MinitestSuiteCommand`,
`MinitestTestRunner`, `MinitestLoadPath`, `RailsEnvironmentPreloader` (each with its
own spec) — and drove `cleanup_suite_process`/`spawn_suite_process` through the
already-public `run_suite` with stubbed inputs. `minitest_spec.rb` no longer calls
`.send` anywhere. Side effect: raised `Henitai::Integration::Minitest` mutation score
from MS 72.83%/MSI 43.05% to MS 100%/MSI 91.87%. Surfaced a follow-up ticket
(`2026-07-09-equivalent-mutant-detection-gap.md`) for two mutants that are genuinely
equivalent, not testable.
