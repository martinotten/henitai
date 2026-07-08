# `integration/minitest_spec` Uses `send` to Reach Private Integration Helpers

Status: backlog
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
