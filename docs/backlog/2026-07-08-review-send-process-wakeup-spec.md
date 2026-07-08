# `process_wakeup_spec` Uses `send` to Reach Private IO Helpers

Status: backlog
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/process_wakeup_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/process_wakeup_spec.rb)
uses `send` to inspect private reader/writer helpers.

## Problem

- The spec is testing internal wiring rather than wakeup behavior.
- It will fail on safe refactors to the IO encapsulation.

## Fix Sketch

- Keep the focus on the observable wakeup behavior.
- Remove private helper assertions if the public behavior already covers them.

## Test Plan

- Replace direct `send` calls with behavior-level assertions around wakeup
  semantics.
