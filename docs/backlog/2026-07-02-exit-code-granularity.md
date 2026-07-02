# Finer-Grained CLI Exit Codes

Status: backlog
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `cargo-mutants`

## Summary

`cargo-mutants` distinguishes outcomes via distinct exit codes (0 all
caught, 2 some missed, 3 timeouts occurred, 70 internal error, etc.), so a
CI script can branch on *why* a run "failed" without parsing output.
Henitai's CLI collapses everything to three codes: `0` (threshold met),
`1` (threshold not met), `2` (framework error) — documented in `CLAUDE.md`
and implemented in `exit_status_for` (`lib/henitai/cli/run_command.rb:79`).

## Problem

`exit_status_for` only branches on `partial_rerun?` and the threshold
comparison. A CI consumer currently cannot tell, from the exit code alone:

- whether the run failed because mutants survived vs. timed out vs. hit
  runtime/compile errors — all bucket into the same `1`.
- whether a `2` was a genuine framework bug vs. a config/environment
  problem (missing coverage, bad `--survivors-from` path, etc.) — all
  uncaught `StandardError`s funnel through `handle_run_error`
  (`lib/henitai/cli/command_support.rb:45`) to the same code.

This makes CI scripting coarser than it could be (e.g. "retry once on
framework error but never on a real mutation-score failure" isn't
distinguishable today).

## Proposed Behavior

This is exit-code contract that's already documented as public API
(`CLAUDE.md`: "`henitai run` exit codes: `0` ... `1` ... `2` ..."), so this
must be **additive, not breaking**:

- Keep `0`/`1`/`2` meaning exactly what they mean today as the *default*
  behavior — existing CI configs must not silently start failing or
  passing differently.
- Add an opt-in `--strict-exit-codes` (or similar) flag that expands the
  code space for callers who want it, e.g.:
  - `0` — threshold met, no timeouts/errors
  - `1` — threshold not met (survivors only)
  - `3` — one or more mutants timed out
  - `4` — one or more mutants hit `:runtime_error`/`:compile_error` beyond
    what static filtering was expected to catch
  - `2` — framework error (unchanged)
- Without the flag, behavior is byte-for-byte identical to today.

## Non-Goals

- Not changing the default exit-code contract — this is the one place
  where "additive" really matters; the existing three codes are load-
  bearing for anyone's CI today.
- Not adding per-outcome exit codes for every `Mutant::STATUSES` value —
  scope to the handful CI scripts actually branch on (survived vs. timeout
  vs. framework error), matching `cargo-mutants`' practical subset rather
  than its full internal taxonomy.

## Open Questions

- Exact flag name and code assignments — needs to avoid colliding with
  shell/POSIX-reserved low exit codes (126-165, 128+signal) the way
  `cargo-mutants` had to think about (it stops at 70).
- **Precedence when conditions co-occur.** A run can simultaneously miss
  the threshold, have timeouts, and have runtime/compile errors — which
  code wins under `--strict-exit-codes`? Needs an explicit priority order
  (e.g. framework error > timeout > runtime/compile error > threshold
  miss), not left implicit.
- Timeouts already interact with `coverage_criteria.timeout` (whether a
  timeout counts as a kill for MS purposes) — a run can pass its threshold
  overall (timeouts counted as kills) while still exiting non-zero for
  "had timeouts" under the new code. That's arguably correct (informational,
  not a threshold failure) but should be stated explicitly so it isn't
  read as a contradiction.
- Should `--fail-on-survivors` (existing partial-rerun flag,
  `lib/henitai/cli/run_command.rb:82`) compose with the new flag, or are
  they orthogonal enough to just both apply independently? Likely
  orthogonal — `--fail-on-survivors` is about partial-rerun semantics only.

## Implementation Notes

- `lib/henitai/cli/run_command.rb#exit_status_for` is the single seam;
  the new codes derive from `Result#mutants` status counts, already fully
  available (`result.mutants.count { |m| m.status == :timeout }`, etc.) —
  no new data plumbing needed, purely a CLI-layer decision.
- `CLAUDE.md`'s exit-code line needs updating once landed, documenting both
  the default and `--strict-exit-codes` tables.
