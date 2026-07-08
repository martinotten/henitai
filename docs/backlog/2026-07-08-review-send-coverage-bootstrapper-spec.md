# `coverage_bootstrapper_spec` Uses `send` to Reach Private Freshness Helpers

Status: backlog
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
