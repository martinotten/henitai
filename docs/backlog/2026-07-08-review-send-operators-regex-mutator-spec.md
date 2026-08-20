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
