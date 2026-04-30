# Survivor-Only Rerun

Status: backlog
Date: 2026-04-07

## Summary

Add a survivor-only rerun mode so Henitai can re-execute only the mutants that survived a previous mutation run. The goal is to speed up the feedback loop when a developer is actively removing survivors and wants to focus on the remaining gaps instead of regenerating and running the full mutant set again.

## Problem

Today, Henitai always regenerates the current mutant set for the selected subjects, filters it, and executes every pending mutant. That is the right default for a full mutation run, but it makes iterative cleanup slower when the developer already knows which mutants survived the last run.

Henitai already persists mutant history for trend tracking, but that history is intentionally separate from the core pass/fail model. This feature would reuse that persisted data as input for a new, explicit rerun mode.

As long as only the test cases change we can assume that the killed mutants want survive because of the changes amde to the tests and become survivors. As this could happen it would speed up killing mutants if we have the ability to re-run only survivors before doing a full run on the code before a commit for validation.

## Proposed Behavior

A survivor-only rerun should:

- read a prior run’s survivor set from the persisted history or saved report data
- regenerate the current mutants for the same subject scope
- match current mutants against the previously survived mutant identity
- execute only the matching mutants
- report the run as a partial rerun, not as a replacement for a full mutation pass

## Identity And Selection

The rerun mode should rely on the existing stable mutant identity rather than line numbers alone. That identity is already derived from the mutant expression, operator, description, location, and mutation signature.

Selection should be explicit and conservative:

- if a prior survivor cannot be matched to the current code, report it clearly
- if the source changed enough that the identity no longer matches, skip or flag the mutant rather than guessing
- do not silently treat the rerun as a full mutation run

## Suggested User Interface

This is not decided yet, but the likely shapes are:

- a dedicated command such as `henitai rerun-survivors`
- or a `run` subcommand option such as `--survivors-from <path>`

A dedicated command is safer if the rerun is meant to be obviously partial, because it reduces the risk of confusing the output with a complete mutation score.

## Report Semantics

The rerun mode needs its own reporting rules.

- The default full-run mutation score should remain unchanged.
- A survivor-only rerun should not pretend to be a fresh whole-project score unless the result is merged with the original full run.
- The report should make clear which mutants were selected from prior survivors.

## Non-Goals

This feature should not:

- change the default `henitai run` behavior
- replace flaky retry handling for a single mutant
- alter latent-mutant history tracking
- depend on external services

## Open Questions

- Should the source of truth be `mutation-report.json`, `mutation-history.sqlite3`, or both?
- Should the rerun accept a saved survivor list as input, or derive survivors directly from the latest report on disk?
- Should the rerun emit a dedicated report format for partial runs?
- Should missing mutants be treated as warnings, skips, or hard errors?

## Implementation Notes

The current codebase already has the building blocks needed for a later implementation:

- stable mutant ids in `MutantHistoryStore`
- persisted per-mutant history in SQLite
- Stryker-compatible JSON output with mutant ids and statuses
- the normal pipeline boundary in `Runner` where a new selection stage could be inserted

The missing piece is a first-class selection step that can load prior survivors and filter the current mutant list before execution.
