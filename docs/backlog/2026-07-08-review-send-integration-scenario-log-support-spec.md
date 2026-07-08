# `integration/scenario_log_support_spec` Uses `send` to Reach Private Log Helpers

Status: backlog
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
