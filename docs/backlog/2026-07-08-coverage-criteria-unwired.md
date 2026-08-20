# `coverage_criteria` Config Is Validated but Never Consumed

Status: done (2026-08-21)
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

## Resolution (2026-08-21)

Wired, with a correction to this ticket's premise.

This ticket assumed the default was `timeout: true` and therefore that wiring
it up would be behavior-preserving. The shipped default was `timeout: false`
(and `process_abort: false`), while `Result#detected_in` counted `:timeout` and
`:runtime_error` as detected unconditionally — so the documented configuration
already contradicted the scorer. Wiring it faithfully would have silently
dropped timeouts and aborts out of every user's MS numerator.

Both defaults were therefore flipped to `true`, which makes the knob mean what
it says while leaving every score unchanged.

- `Result::CRITERION_STATUSES` maps `test_result` -> `:killed`,
  `timeout` -> `:timeout`, `process_abort` -> `:runtime_error`. That mapping
  was unresolved in this ticket; `process_abort` is forward-looking wiring,
  since nothing in `lib/` currently classifies a mutant as `:runtime_error`.
- `Result::DEFAULT_COVERAGE_CRITERIA` duplicates the Configuration constant
  rather than reading it, following the existing `DEFAULT_THRESHOLDS`
  precedent: `Result` is a domain object and must not depend on configuration
  loading. A spec asserts the two constants stay equal so they cannot drift.
- `MSI` needed no work — `killed / total` is criteria-independent by
  construction.
- `CheckpointReporter` takes no criteria argument on purpose:
  `to_stryker_schema` does not consume `detected`, so there is nothing for it
  to pass through.
- `assets/schema/henitai.schema.json` needed no edit: it encodes types, and
  `spec/infra/configuration_schema_spec.rb` asserts key lists. Neither changed.

Open follow-up: `test_result: false` is a foot-gun — it leaves the numerator as
timeouts and aborts only. A validator warning would be reasonable and is not
implemented.
