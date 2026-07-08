# `runner_spec` Uses `send` to Reach Private Runner Helpers

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/runner_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/runner_spec.rb)
uses `send` for runner internals such as path normalization, threshold
resolution, and dirty-source detection.

## Problem

- The file heavily exercises private helpers instead of the public runner flow.
- This makes it fragile against refactors in the orchestration layer.

## Fix Sketch

- Prefer end-to-end runner scenarios through `run`.
- Keep a minimal set of helper tests only if they are truly necessary.

## Test Plan

- Remove or reduce `send` calls by testing the public runner outcomes.
- Preserve only behavior that is externally visible to callers.
