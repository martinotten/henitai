# `integration/rspec_spec` Uses `send` to Reach Private Adapter Helpers

Status: backlog
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
