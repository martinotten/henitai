# `integration/child_debug_support_spec` Uses `send` to Reach Private Debug Helpers

Status: backlog
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/integration/child_debug_support_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/integration/child_debug_support_spec.rb)
reaches into private helper methods with `send`, including debug-child
inspection and example-count helpers.

## Problem

- The spec is coupled to helper names and signatures instead of observable
  behavior.
- Refactors inside the support module will force test churn.

## Fix Sketch

- Cover the debug behavior through the public integration path that consumes
  the support module.
- Keep helper-level tests only where a public seam exists.

## Test Plan

- Remove `send` calls from the support spec.
- Add behavior-level assertions around the integration entry point.
