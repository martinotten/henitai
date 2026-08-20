# `slot_scheduler_spec` Uses `send` to Reach Private Scheduling Helpers

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/slot_scheduler_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/slot_scheduler_spec.rb)
uses `send` to exercise private slot bookkeeping and timeout helpers.

## Problem

- The tests are strongly coupled to internal scheduler implementation.
- They are more brittle than the public scheduling behavior requires.

## Fix Sketch

- Move the important checks to the public scheduling flow.
- Retain only the smallest private-helper coverage if needed.

## Test Plan

- Replace `send` calls with public scheduling scenarios.
- Verify slot dispatch and timeout behavior through the scheduler API.

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
