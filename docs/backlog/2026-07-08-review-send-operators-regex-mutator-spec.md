# `operators/regex_mutator_spec` Uses `send` to Reach Private Mutator Helpers

Status: backlog
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/operators/regex_mutator_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/operators/regex_mutator_spec.rb)
uses `send` to reach private regex-mutator helpers.

## Problem

- The spec reaches into implementation details rather than the mutator's public
  behavior.
- The helper-level assertions are brittle if the internal algorithm changes.

## Fix Sketch

- Prefer public mutator behavior and generated mutant assertions.
- Keep private-helper tests only if the logic truly has no public seam.

## Test Plan

- Remove the direct `send` calls from the regex mutator spec.
- Verify the generated mutations through the public mutator API.
