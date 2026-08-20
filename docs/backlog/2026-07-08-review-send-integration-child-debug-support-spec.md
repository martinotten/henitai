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

## Convention Note (added 2026-08-21)

The Fix Sketch above says to shift coverage to the public entry points. That
prescription is **superseded**: see
[`2026-07-08-review-send-integration-minitest-spec.md`](2026-07-08-review-send-integration-minitest-spec.md),
the one ticket in this family that was actually resolved. It extracted public
collaborators instead, and took `Henitai::Integration::Minitest` from
MS 72.83% / MSI 43.05% to MS 100% / MSI 91.87%.

This repository scores mutation coverage against itself, so a pure public-API
rewrite usually *loses* coverage — the assertions end up further from the logic
they constrain. Extract a public collaborator; rewrite in place only where a
public path genuinely reaches the behavior.

The budget for this file in `spec/infra/private_method_reach_spec.rb` must come
down in the same commit as any reduction here.
