# CLI Exits 1 on an Empty Mutant Set

Status: done
Date: 2026-06-16
Severity: Medium
Source: surfaced by CI on a test-only PR (#3)

## Summary

`henitai run` exits 1 when no valid mutants are evaluated (e.g. an incremental
`--since` run on a change that touches no mutable code). This fails CI on every
test-only or docs-only change, even though nothing regressed.

## Problem

`CLI#exit_status_for` (lib/henitai/cli.rb) computed
`result.mutation_score.to_i >= threshold ? 0 : 1`. `Result#mutation_score`
returns `nil` when there are no valid mutants; `nil.to_i` is `0`, which is below
the default low threshold (60), so the run exited 1.

Observed on PR #3 (a spec-only change): the incremental mutation job reported
`Killed 0 / Survived 0 / MS n/a` and exited 1.

## Fix

`exit_status_for` returns 0 when `mutation_score` is `nil` — there are no valid
mutants to evaluate, so no threshold can be failed. Threshold evaluation still
applies whenever at least one valid mutant exists.

Covered by a cli_spec example: "exits zero when there are no valid mutants to
evaluate".
