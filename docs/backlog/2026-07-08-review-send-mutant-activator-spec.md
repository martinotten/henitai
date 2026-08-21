# `mutant/activator_spec` Uses `send` to Reach Private Activation Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/mutant/activator_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/mutant/activator_spec.rb)
uses `send` heavily to assert private activation helpers such as target
resolution, source-body assembly, and replacement internals.

## Problem

- The spec couples itself to implementation details inside the activator.
- The file will be fragile across refactors that preserve public behavior.

## Fix Sketch

- Prefer behavior coverage through the activator's public API.
- Keep helper coverage only for logic that is genuinely unavoidably private.

## Test Plan

- Remove direct `send` calls where the same behavior can be exercised through the
  activator interface.
- Keep only the minimum private-helper coverage needed to protect tricky logic.

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
