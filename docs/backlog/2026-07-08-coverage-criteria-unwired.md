# `coverage_criteria` Config Is Validated but Never Consumed

Status: backlog
Date: 2026-07-08
Severity: Low
Source: discovered while switching the dogfood config to calibrated timeouts

## Summary

`.henitai.yml`'s `coverage_criteria` block (`test_result`, `timeout`,
`process_abort`) is schema-documented, validated by
`ConfigurationValidator`, defaulted and exposed by
`Configuration#coverage_criteria` — and then read by nothing. Scoring in
`lib/henitai/result.rb` hardcodes `MS = (killed + timeout) / …`; whether a
timeout counts as a kill cannot actually be configured, despite the config
surface (and the auto-calibrated-timeout ticket's discussion) implying it
can.

## Problem

- Users flipping `coverage_criteria.timeout: false` expect timed-out
  mutants to stop counting as kills; the setting silently does nothing.
- The strict-exit-codes and auto-calibrated-timeout docs both reference
  `coverage_criteria.timeout` semantics that are not implemented.

## Fix Sketch

Either wire it — `Result`'s scoring consults the config when classifying
`:timeout` for the MS numerator (default `true`, current behavior) — or
remove the block from schema/validator/docs. Wiring is preferable: the
knob is already documented public surface.

## Test Plan

- Result scoring spec matrix: `timeout: true` (today's numbers, unchanged)
  vs `timeout: false` (timeouts drop out of the MS numerator; MSI
  unchanged).
- Config plumb-through spec: Runner passes the criteria into Result.
- Docs: CLAUDE.md scoring section notes the knob.
