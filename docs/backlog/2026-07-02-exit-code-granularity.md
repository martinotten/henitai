# Finer-Grained CLI Exit Codes

Status: backlog
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `cargo-mutants`;
evidence extended 2026-07-06 by the cross-framework round
(`docs/research/cross_framework_comparison.md` §2.5)

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

## Related Option From Cross-Framework Round (added 2026-07-06)

Infection 0.34 gates CI on **two** thresholds: `--min-msi` (killed/total)
and `--min-covered-msi` (killed/covered). Henitai reports MS and MSI
together but only gates on MS (`thresholds.low`). An optional MSI gate
(e.g. `thresholds.msi_low`, exit 1 when unmet) is adjacent to this ticket's
exit-code work and could ride along under the same additive-only
constraint — decide during implementation whether to fold it in or file
separately.

## Implementation Notes

- `lib/henitai/cli/run_command.rb#exit_status_for` is the single seam;
  the new codes derive from `Result#mutants` status counts, already fully
  available (`result.mutants.count { |m| m.status == :timeout }`, etc.) —
  no new data plumbing needed, purely a CLI-layer decision.
- `CLAUDE.md`'s exit-code line needs updating once landed, documenting both
  the default and `--strict-exit-codes` tables.

## Decisions (resolving the Open Questions)

- **Precedence (highest wins):** framework error (`2`) > timeout present
  (`3`) > runtime/compile error present (`4`) > threshold miss (`1`) > `0`.
  A run that both misses the threshold and had timeouts exits `3`.
- **Timeout code is informational**, independent of
  `coverage_criteria.timeout`: a run can pass its threshold (timeouts
  counted as kills) and still exit `3` under `--strict-exit-codes` —
  documented explicitly, not a contradiction.
- **`--fail-on-survivors` stays orthogonal** (partial-rerun semantics
  only); both flags may be combined, `--fail-on-survivors` evaluated first
  in partial reruns as today.
- Codes stop at `4`; nothing in the POSIX-reserved ranges.

## Fix Plan (TDD)

1. **Red.** `spec/henitai/cli/` run-command spec matrix for
   `exit_status_for` with `strict_exit_codes: true`: each condition alone
   (survivors-only miss → 1, timeouts present → 3, runtime/compile errors
   present → 4, all clean + threshold met → 0) plus co-occurrence cases
   proving the precedence order above. Framework-error path (2) asserted
   via the existing `handle_run_error` spec extended with the flag set.
2. **Green.** Branch in `exit_status_for`
   (`lib/henitai/cli/run_command.rb`) deriving counts from
   `result.mutants` statuses; only active when the flag is set.
3. **Red.** Guard spec: with the flag absent, the full existing
   exit-status spec set passes **unmodified** (no edits to existing
   examples allowed — that's the additive-contract proof).
4. **Green/verify.** No-op by construction; run the suite.
5. **Red.** `options_spec`: `--strict-exit-codes` parses into
   `options[:strict_exit_codes]`.
6. **Green.** `add_strict_exit_codes_option` in
   `lib/henitai/cli/options.rb` following the existing pattern; help text
   includes the code table.
7. Update `CLAUDE.md` exit-code section (default + strict tables).
8. Refactor, rubocop, full suite.

## Acceptance

- Default (no flag): byte-identical exit behavior; zero existing spec
  files modified.
- With flag: codes 0/1/2/3/4 per the documented precedence; every
  co-occurrence case deterministic.
- Partial reruns: `--fail-on-survivors` semantics unchanged with and
  without the new flag.
- `henitai run --help` and `CLAUDE.md` document both tables.

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | run-command spec matrix: 4 single-condition cases + ≥3 precedence co-occurrence cases + framework-error-with-flag |
| Unit | contract guard: default-path specs untouched and green |
| Unit | option-parsing spec |
| Integration | rspec smoke fixture invoked with `--strict-exit-codes` on a run with a known survivor → `$?` is 1; with an injected timeout scenario → 3 (reuse the execution-engine timeout fixture pattern) |
| Docs | `CLAUDE.md` table matches help text (manual check in PR review) |
