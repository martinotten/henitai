# Machine-Readable Survivor Worklist

Status: proposed
Date: 2026-11-13
Severity: Medium (closing survivors is the main use of the tool; today it
needs ad-hoc parsing of `mutation-report.json`)
Source: requirement intake 2026-11-12.

## Summary

The work that follows a run is "write a test that kills each survivor".
Coding agents and scripts do this today by parsing the Stryker
`mutation-report.json`, which is built for dashboards: positions instead of
source lines, mutated text without the original, no link to the tests that
already cover the line. Provide a stable, compact worklist format and a
loop to re-check single survivors cheaply.

## Requirements

1. **Worklist format** (`henitai survivors --format json|text`, reading the
   canonical report; no new run):
   - per survivor: stable id, file, line range, subject expression,
     operator, original source snippet, mutated snippet (or unified diff),
     covering test files (from `covered_by` / per-test coverage), status
     reason;
   - sorted by file and line; grouped per subject;
   - a JSON Schema in `assets/schema/`, versioned; stable field names are
     public API.
2. **Targeted re-check:** `henitai run --mutant <stable-id>` (or
   `--survivors-from` filtered to ids) re-runs exactly the given mutants
   against the current tests, using verdict reuse rules unchanged
   (ADR-11), and prints the new verdict per id.
3. **Exit codes** for the re-check: 0 when all given mutants are killed,
   1 when any survives — usable as a loop condition.
4. Text format suitable for a terminal and for pasting into an issue.

## Non-goals

- No test generation inside henitai.
- No change to the Stryker report schema; the worklist is derived from it.

## Open questions

- Does `--survivors-from` with an id filter already cover requirement 2,
  or is a new flag clearer?
- Should equivalent-mutant candidates (`EquivalenceDetector`) be listed
  separately so nobody writes tests for them?

## Acceptance criteria

- On this repository's report, `henitai survivors --format json` validates
  against the schema and lists every `Survived` mutant with original and
  mutated source and covering tests.
- Killing one survivor and re-checking its id reports it as `Killed` and
  exits 0, without running other mutants.

## Related

- `lib/henitai/survivor_loader.rb`, `lib/henitai/survivor_selector.rb`,
  `lib/henitai/reporter.rb`
- `docs/backlog/2026-07-14-stats-command.md` (read-only aggregation from the
  same artifacts — share the report-reading code)
