# `mutant_generator_spec` Uses `send` to Reach Private Generation Helpers

Status: done (2026-08-21)
Date: 2026-07-08
Severity: Medium
Source: discovered while auditing specs that call private methods with `send`

## Summary

[`spec/henitai/mutant_generator_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/mutant_generator_spec.rb)
uses `send` to inspect private generation helpers, including sampling and node
range checks.

## Problem

- The spec asserts internals instead of the generator's external contract.
- It is at risk of breaking on helper extraction or renaming.

## Fix Sketch

- Move the important assertions to the public mutant-generation path.
- Keep only a small number of private-helper specs if no public seam exists.

## Test Plan

- Remove direct `send` calls from the generator spec where possible.
- Add public-behavior assertions for subject filtering and sampling outcomes.

## Resolution (2026-08-21)

Already satisfied. The named spec file reaches zero private methods at HEAD --
the debt was paid down incidentally by other work (notably the
mutation-coverage paydown in `1636e1b` and `99aa8bc`) rather than by this
ticket, which is why the status sat stale.

Verified by `spec/infra/private_method_reach_spec.rb`, whose budget list does
not contain this file. That guard permits no unbudgeted spec any private
reach, so the debt cannot return here unnoticed -- which is the part that
previously failed: while these twelve tickets were open, the same coupling
regrew into three *different* files that nobody had ticketed
(`slot_scheduler/draining_spec.rb`, `equivalence_detector_spec.rb`,
`execution_engine_spec.rb`).
