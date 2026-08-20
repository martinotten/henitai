# `integration/scenario_log_support_spec` Uses `send` to Reach Private Log Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/integration/scenario_log_support_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/integration/scenario_log_support_spec.rb)
uses `send` to inspect private scenario-log helper methods.

## Problem

- The spec checks internals instead of the behavior the support module provides.
- The tests will be brittle if the helper names or flow change.

## Fix Sketch

- Move assertions to the public behavior that consumes the support helpers.
- Retain private-helper coverage only if no public contract exists.

## Test Plan

- Remove direct `send` calls from the support spec.
- Verify the resulting log-path behavior through the public path.

## Resolution (2026-08-21)

Already satisfied. The named spec file reaches zero private methods at HEAD --
the debt was paid down incidentally by other work (notably the
mutation-coverage paydown in `1636e1b` and `99aa8bc`) rather than by this
ticket, which is why the status sat stale.

Verified by `spec/infra/private_method_reach_spec.rb`, whose budget list does
not contain this file. That guard permits no unbudgeted spec any private
reach, so the debt cannot return here unnoticed -- which is the part that
previously failed: while these twelve tickets were open, the same coupling
regrew into three *different* files that nobody had ticketed
(`slot_scheduler/draining_spec.rb`, `equivalence_detector_spec.rb`,
`execution_engine_spec.rb`).
