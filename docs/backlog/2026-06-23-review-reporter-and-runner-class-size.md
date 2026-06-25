# Oversized Classes: Reporter (529) and ProcessWorkerRunner (448)

Status: backlog
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

## Fix Plan

1. **reporter.rb — extract infra at the edges (TDD per extraction):**
   - `DashboardMetadataProvider` (inject env getter + git executor) owning
     project/version/api-key/remote/branch resolution. Spec it with injected
     fakes — no real ENV/git.
   - `FileReporter` (or reuse an existing IO seam) owning canonical/snapshot/
     history writes. Inject the IO seam already used by `Reporter::Json` after
     the 2026-06-16 IO-injection work.
   - Inject `color_enabled` into `Reporter::Terminal` instead of reading
     `NO_COLOR` inline.
   - Each extraction: write the failing unit spec against the new seam first,
     then move code, then delete the inline I/O.
2. **process_worker_runner.rb — split lifecycle from scheduling:**
   - Extract a `ProcessReaper` (reap/drain/prune of children) and keep
     `ProcessWorkerRunner` as the scheduler. Move the `AbcSize`-disabled
     methods into the reaper where they become single-responsibility and the
     disables can be dropped.
   - Keep `Slot` as the lifecycle state holder.
   - Characterize current behavior with the existing barrier/real-process specs
     before refactoring; keep them green throughout.
3. **Remove the rubocop disables** once methods fit the limits. Per AGENTS.md:
   no fresh offenses, no blanket disables.
4. Run rubocop + full suite + a dogfood `henitai run` after each class.

## Acceptance

- Both classes under 200 lines (or justified, documented exceptions).
- No `Metrics/AbcSize`/`ClassLength` disables remain in these files.
- Reporters unit-testable without touching real ENV/git/filesystem.
- Suite + rubocop green.

## Related

- [[2026-06-16-review-class-size-discipline]]
- [[2026-06-16-review-domain-io-leakage]]
- [[2026-06-23-review-dead-parallel-runner]]
