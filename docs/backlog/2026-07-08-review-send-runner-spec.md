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
