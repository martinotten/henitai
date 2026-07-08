# `mutant/activator_spec` Uses `send` to Reach Private Activation Helpers

Status: backlog
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/mutant/activator_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/mutant/activator_spec.rb)
uses `send` heavily to assert private activation helpers such as target
resolution, source-body assembly, and replacement internals.

## Problem

- The spec couples itself to implementation details inside the activator.
- The file will be fragile across refactors that preserve public behavior.

## Fix Sketch

- Prefer behavior coverage through the activator's public API.
- Keep helper coverage only for logic that is genuinely unavoidably private.

## Test Plan

- Remove direct `send` calls where the same behavior can be exercised through the
  activator interface.
- Keep only the minimum private-helper coverage needed to protect tricky logic.
