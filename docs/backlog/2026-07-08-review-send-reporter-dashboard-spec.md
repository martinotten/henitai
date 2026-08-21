# `reporter/dashboard_spec` Uses `send` to Reach Private Reporter Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/reporter/dashboard_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/reporter/dashboard_spec.rb)
uses `send` to inspect a private project-helper method.

## Problem

- The spec is coupled to the reporter's internal structure.
- The test surface is larger than the public dashboard behavior needs.

## Fix Sketch

- Cover the reporter through its public rendering/output path.
- Remove private helper assertions where possible.

## Test Plan

- Delete `send` usage from the dashboard reporter spec.
- Verify the configured project shows up through the public report output.

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
