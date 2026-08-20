# `integration/rspec_spec` Uses `send` to Reach Private Adapter Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/integration/rspec_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/integration/rspec_spec.rb)
calls many private adapter helpers directly, including command building, file
selection, timeout handling, and log-path utilities.

## Problem

- This spec is a thin wrapper around internal methods instead of the public RSpec
  integration contract.
- It will overreact to internal refactors that do not change behavior.

## Fix Sketch

- Keep behavior coverage on the public integration runner paths.
- Delete helper-only assertions where the same behavior is already covered
  through the adapter entry point.

## Test Plan

- Replace the private-helper calls with public integration scenarios.
- Preserve only the user-facing outcomes of RSpec execution.

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
