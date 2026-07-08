# `reporter/terminal_spec` Uses `send` to Reach Private Formatting Helpers

Status: backlog
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
