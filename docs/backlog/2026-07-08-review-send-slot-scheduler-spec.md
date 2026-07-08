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
