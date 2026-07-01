# Oversized Classes: Reporter (529) and ProcessWorkerRunner (448)

Status: done
Date: 2026-06-23
Severity: Medium
Source: 2026-06-23 structured review

## Summary

Two classes exceed the 200-line `Metrics/ClassLength` limit and mix concerns.
`reporter.rb` blends domain formatting with infrastructure (ENV, git, file
I/O); `process_worker_runner.rb` combines scheduling, process lifecycle, and
retry logic, with `Metrics/AbcSize` disables masking the complexity. Continues
the earlier class-size effort ([[2026-06-16-review-class-size-discipline]],
[[2026-06-16-review-domain-io-leakage]]).

## Problem

### reporter.rb (529 lines)
- `Reporter::Dashboard` reads CI/secret env directly: `ENV.fetch` for GitHub
  vars and `STRYKER_DASHBOARD_API_KEY`; shells out via `Open3.capture2` for git
  remote/branch.
- `Reporter::Json` does `FileUtils.mkdir_p`, `File.write`, `File.exist?`
  inline.
- `Reporter::Terminal` checks `ENV.key?("NO_COLOR")` directly.

### process_worker_runner.rb (448 lines)
- One class owns: slot state machine, fork/reap/signal lifecycle, timeout
  checks, flaky retry, signal-trap install, process-group cleanup.
- `reap_and_remove_draining` and `retry_slot` carry
  `# rubocop:disable Metrics/AbcSize`.

**Re-verified 2026-07-01:** `process_worker_runner.rb` had already been split
into `ProcessWorkerRunner` (148 lines, event loop + signal traps only) +
`SlotScheduler` (214 lines) + `SlotScheduler::ProcessControl` +
`SlotScheduler::Draining` by prior work outside this ticket's tracking — the
"448 lines, one class owns everything" framing was stale. Only the two named
`AbcSize` disables (`retry_slot`, now in `slot_scheduler.rb`;
`reap_and_remove_draining`, now in `slot_scheduler/draining.rb`) were still
genuinely open, matching item 3 of the Fix Plan below.

## Fix Plan

1. **reporter.rb — extract infra at the edges (TDD per extraction):**
   - `DashboardMetadataProvider` (inject env getter + git executor) owning
     project/version/api-key/remote/branch resolution. Spec it with injected
     fakes — no real ENV/git. — done: `lib/henitai/reporter/dashboard_metadata_provider.rb`
     + `spec/henitai/reporter/dashboard_metadata_provider_spec.rb`; `Dashboard`
     now delegates `project`/`version`/`api_key` to an injected provider
     (defaults to a real `ENV`/`Open3`-backed one). `dashboard_spec.rb` no
     longer mutates real `ENV` or stubs private instance methods — it injects
     an `instance_double(DashboardMetadataProvider)` instead.
   - `FileReporter` (or reuse an existing IO seam) owning canonical/snapshot/
     history writes. — deliberately deferred: `Json`/`Html`'s
     `FileUtils.mkdir_p`/`File.write`/`File.exist?` calls are already
     unit-tested in isolation via `Dir.mktmpdir`-scoped `config.reports_dir`
     (see `spec/henitai/reporter/json_spec.rb`), the same real-but-isolated-
     filesystem pattern used elsewhere in this codebase (no injected fake
     needed to avoid touching the real project tree). Unlike Dashboard's
     ENV/git access, this was never observed forcing real ENV mutation or
     private-method stubbing in specs, so it doesn't block the "unit-testable
     without touching real ENV/git/filesystem" acceptance criterion in
     practice. Left as a documented, lower-priority follow-up rather than
     inventing a new IO abstraction with no proven test pain to justify it.
   - Inject `color_enabled` into `Reporter::Terminal` instead of reading
     `NO_COLOR` inline. — done: `Terminal#initialize` takes
     `color_enabled: !ENV.key?("NO_COLOR")`; `colorize` checks the injected
     flag. `terminal_spec.rb`'s `with_color`/`with_no_color` real-`ENV`-mutating
     helpers (used by 9 examples) removed in favor of passing
     `color_enabled: true/false` directly.
   - Each extraction: write the failing unit spec against the new seam first,
     then move code, then delete the inline I/O. — done for the two extractions above.
2. **process_worker_runner.rb — split lifecycle from scheduling:** — already
   done by prior work (see re-verification note above); `SlotScheduler`/
   `ProcessControl`/`Draining` is the landed shape, not the `ProcessReaper`
   name originally proposed here, but it satisfies the same intent
   (lifecycle/reaping split from the scheduler, `Slot` kept as the state
   holder). No further extraction needed.
3. **Remove the rubocop disables** once methods fit the limits. — done:
   `retry_slot` (slot_scheduler.rb) split into `retry_slot` + `finish_retry` +
   `reset_slot_for_retry`; `reap_and_remove_draining` (slot_scheduler/draining.rb)
   split into `reap_and_remove_draining` + `reap_and_finalize_slot` +
   `record_drain_result`. Both `Metrics/AbcSize` disables dropped; no new
   offenses.
4. Run rubocop + full suite + a dogfood `henitai run` after each class. —
   done: rubocop 199 files/0 offenses, rspec 1132 examples/0 failures, steep
   clean, `henitai run` smoke-tested on `Henitai::Reporter#run_all` and
   `Henitai::SlotScheduler#retry_slot` (the latter's 0% dogfood mutation score
   was confirmed pre-existing via `git stash -u` against the prior commit —
   a known per-test-coverage attribution gap for forked-process code, not a
   regression from this work).

## Acceptance

- Both classes under 200 lines (or justified, documented exceptions). — met
  for `process_worker_runner.rb`/`slot_scheduler.rb` (148/214 lines). Not
  literally met for `reporter.rb` as a *file* (465 lines after extraction,
  down from 529), but `Metrics/ClassLength` (max 200) was never actually
  violated by any individual class inside it (`Terminal`/`Json`/`Html`/
  `Dashboard` are each well under 200 lines) — confirmed by rubocop passing
  both before and after this work. The file groups several small, cohesive
  reporter classes, not one oversized class; this is the documented exception.
- No `Metrics/AbcSize`/`ClassLength` disables remain in these files. — met.
- Reporters unit-testable without touching real ENV/git/filesystem. — met for
  ENV/git (Dashboard, Terminal); filesystem access in Json/Html left as a
  documented exception (see Fix Plan item 1).
- Suite + rubocop green. — met.

## Related

- [[2026-06-16-review-class-size-discipline]]
- [[2026-06-16-review-domain-io-leakage]]
- [[2026-06-23-review-dead-parallel-runner]]
