# `reporter/terminal_spec` Uses `send` to Reach Private Formatting Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/reporter/terminal_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/reporter/terminal_spec.rb)
calls private formatter helpers with `send`, including score color and flush
behavior.

## Problem

- The spec is pinned to internal formatting helpers instead of the reporter's
  output contract.
- It will be noisy if the implementation is rearranged.

## Fix Sketch

- Assert on rendered terminal output and side effects rather than private helper
  calls.
- Keep only unavoidable helper coverage.

## Test Plan

- Remove direct `send` calls where the same behavior is visible in rendered
  output.
- Add output-based assertions for score color and flush behavior.

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
