# `coverage_bootstrapper_spec` Uses `send` to Reach Private Freshness Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/coverage_bootstrapper_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/coverage_bootstrapper_spec.rb)
still calls private helpers with `send`, including freshness checks around
`watched_files_fresh?`. That makes the spec depend on implementation details
instead of the public bootstrap behavior.

## Problem

- The spec will break on internal refactors even if `ensure!` behaves the same.
- The public contract is coverage bootstrapping, not helper internals.

## Fix Sketch

- Replace private-helper assertions with coverage-bootstrap scenarios through
  `ensure!`.
- Keep only behavior-level coverage for freshness, availability, and
  re-bootstrap decisions.

## Test Plan

- Add or adjust `ensure!` specs for fresh and stale report cases.
- Remove direct `send` calls from the file.

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
