# `reporter/dashboard_spec` Uses `send` to Reach Private Reporter Helpers

Status: backlog
Date: 2026-07-08
Severity: Low
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/reporter/dashboard_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/reporter/dashboard_spec.rb)
uses `send` to inspect a private project-helper method.

## Problem

- The spec is coupled to the reporter's internal structure.
- The test surface is larger than the public dashboard behavior needs.

## Fix Sketch

- Cover the reporter through its public rendering/output path.
- Remove private helper assertions where possible.

## Test Plan

- Delete `send` usage from the dashboard reporter spec.
- Verify the configured project shows up through the public report output.
