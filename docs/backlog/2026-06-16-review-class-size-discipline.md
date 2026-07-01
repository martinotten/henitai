# Restore Class-Size Discipline (Remove rubocop Metrics Disables)

Status: done
Date: 2026-06-16
Severity: Medium
Source: 2026-06-16 structured review

## Summary

`CODE_PRINCIPLES.md` sets a 200-line class / module limit and a 15-line method
limit. Seven files waive the class/module limit with `rubocop:disable` rather
than meeting it. The disables mark a slow erosion of the size contract.

## Problem

`rubocop:disable Metrics/ClassLength` or `Metrics/ModuleLength` in:

- `lib/henitai/integration.rb:116` (953 lines — see god-file issue)
- `lib/henitai/reporter.rb` (517 lines)
- `lib/henitai/cli.rb:21` (484 lines)
- `lib/henitai/process_worker_runner.rb:8` (434 lines)
- `lib/henitai/runner.rb:28` (393 lines)
- `lib/henitai/mutant_history_store.rb:12`
- `lib/henitai/configuration_validator.rb:4`
- `lib/henitai/mutant/activator.rb:9`

## Fix Plan

Tackle one file per PR, each behavior-preserving with specs green.

1. **`reporter.rb`** — splits cleanly by reporter type. Move `Json`, `Html`,
   `Terminal`, `Dashboard` into `lib/henitai/reporter/<name>.rb`; keep a thin
   `Reporter` dispatcher. Also resolves the `Reporter::Json` SQLite-coupling
   issue (separate ticket). — done differently than proposed: rather than one
   file per reporter class, extracted the actual infra leaks
   (`DashboardMetadataProvider` for env/git, injected `color_enabled` for
   `Terminal`) as part of `2026-06-23-review-reporter-and-runner-class-size`.
   No `Metrics/ClassLength` disable was ever actually present on `reporter.rb`
   (each nested reporter class is independently well under 200 lines — the
   529-line figure was the whole file, not one oversized class), so the
   original premise of this item was slightly off; the real problem (infra
   mixed into domain reporters) is what got fixed.
2. **`runner.rb`** — extract the survivor-rerun fast path (recipe loading, stub
   construction, drift-warning, `finalize_survivor_split`) into a
   `SurvivorRerunStrategy` object. Runner keeps orchestration only. — done
   (prior work; `runner.rb` is 270 lines with no `ClassLength` disable,
   `SurvivorRerunStrategy` exercised directly in `runner_spec.rb`).
3. **`cli.rb`** — extract per-command handlers into command objects or a
   `Commands` module; CLI keeps arg parsing + dispatch. — done (prior work;
   `cli.rb` is 96 lines, command objects live in `lib/henitai/cli/`).
4. **`process_worker_runner.rb`** — extract the drain/timeout state machine
   (slot lifecycle, broadcast/reap) into a `SlotScheduler` collaborator. —
   done (prior work landed `SlotScheduler`/`ProcessControl`/`Draining`,
   not the `ProcessReaper` name originally proposed here, but the same split;
   `process_worker_runner.rb` is now 148 lines with no disable).
5. **`mutant_history_store.rb` / `configuration_validator.rb` /
   `mutant/activator.rb`** — assess; extract query builders / validation rule
   groups where it reduces size without inventing indirection. — done (prior
   work: `Sql` extracted from `mutant_history_store.rb`, `Rules`/`Scalars`
   from `configuration_validator.rb`, `ParameterSource` from
   `mutant/activator.rb`; all three now well under 200 lines with no disable).
6. Remove each `rubocop:disable` as its file drops under 200 lines. Add to
   review checklist: no new `Metrics/*Length` disables. — done: re-verified
   2026-07-01, `grep -rn "rubocop:disable Metrics/ClassLength\|ModuleLength" lib`
   returns zero matches across the entire `lib/` tree.

## Acceptance

- All listed files under 200 lines OR the disable is replaced with a documented,
  reviewed exception in `.rubocop.yml` (not an inline disable). — met; no
  `.rubocop.yml` exception was even needed, all disables were simply removed.
- `bundle exec rubocop` green; full suite green. — met (199 files/0 offenses,
  1132 examples/0 failures as of 2026-07-01).

## Related

- [[2026-06-16-review-integration-god-file]]
- [[2026-06-16-review-domain-io-leakage]]
