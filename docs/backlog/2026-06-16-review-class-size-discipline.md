# Restore Class-Size Discipline (Remove rubocop Metrics Disables)

Status: partial
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
   issue (separate ticket).
2. **`runner.rb`** — extract the survivor-rerun fast path (recipe loading, stub
   construction, drift-warning, `finalize_survivor_split`) into a
   `SurvivorRerunStrategy` object. Runner keeps orchestration only.
3. **`cli.rb`** — extract per-command handlers into command objects or a
   `Commands` module; CLI keeps arg parsing + dispatch.
4. **`process_worker_runner.rb`** — extract the drain/timeout state machine
   (slot lifecycle, broadcast/reap) into a `SlotScheduler` collaborator.
5. **`mutant_history_store.rb` / `configuration_validator.rb` /
   `mutant/activator.rb`** — assess; extract query builders / validation rule
   groups where it reduces size without inventing indirection.
6. Remove each `rubocop:disable` as its file drops under 200 lines. Add to
   review checklist: no new `Metrics/*Length` disables.

## Acceptance

- All listed files under 200 lines OR the disable is replaced with a documented,
  reviewed exception in `.rubocop.yml` (not an inline disable).
- `bundle exec rubocop` green; full suite green.

## Related

- [[2026-06-16-review-integration-god-file]]
- [[2026-06-16-review-domain-io-leakage]]
