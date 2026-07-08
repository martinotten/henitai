# `mutant_generator_spec` Uses `send` to Reach Private Generation Helpers

Status: backlog
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
