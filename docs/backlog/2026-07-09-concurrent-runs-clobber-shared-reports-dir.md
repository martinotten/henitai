# Concurrent Runs Silently Clobber a Shared reports_dir

Status: done (shipped 0.3.0; status flipped 2026-08-21)
Date: 2026-07-09
Severity: Medium
Source: observed live — two `henitai run` invocations against the same repo
(one via terminal, one launched in the background) wrote the same
`reports/mutation-report.json` concurrently. The on-disk report grew to ~5 MB,
larger than either run alone: a merge of two different runs (different operator
sets / sampling), leaving an untrustworthy report and HTML while each run's own
terminal summary stayed correct.

## Summary

henitai has no guard against two runs targeting the same `reports_dir` at once.
Both the incremental `CheckpointReporter` and the end-of-run `Reporter::Json`
write `<reports_dir>/mutation-report.json` (via `CanonicalReportWriter`), and
non-authoritative writes merge-by-`stableId` into whatever is already on disk
(`CanonicalReportMerger`). Two overlapping runs therefore interleave and merge
each other's mutants into one file — last-writer-wins per flush, with
cross-run contamination. The same applies to `mutation-report.html`,
`mutation-history.sqlite3`, `henitai_per_test.json` and the
`mutation-coverage/` / `mutation-logs/` trees, all keyed only by `reports_dir`.

The individual runs' terminal summaries are unaffected (computed live from each
run's own in-memory mutants), so the corruption is silent — only the persisted
artifacts are wrong, and only if someone compares them to the terminal output.

This is distinct from, but compounded by, the checkpoint/merge feature added
2026-07-09: incremental flushing widens the window in which a second run can
observe and merge a half-written report.

## Impact

- A background/CI run plus a local run (or two CI jobs sharing a cache dir)
  produce a merged, wrong `mutation-report.json` / HTML / dashboard upload.
- Silent: no error, no warning; the terminal looks fine, the file lies.
- Wasted machine load: two full fork trees competing for the same box.

## Fix Sketch

Acquire an exclusive per-`reports_dir` lock at run start; refuse (or wait) if
another live run holds it.

- On `Runner#run` start, create `<reports_dir>/.henitai-run.lock` and take an
  advisory exclusive lock (`File#flock(File::LOCK_EX | File::LOCK_NB)`). flock
  is released automatically when the process dies, so a crashed run does not
  leave a permanently stuck lock (unlike a bare PID file). Write the owning pid
  + start time into the file for a useful diagnostic.
- If the lock is already held: abort with a clear framework error (exit `2`) —
  `"another henitai run is active in <reports_dir> (pid N); use a separate
  reports_dir or wait"`. Consider an opt-in `--wait` to block instead.
- Release in an `ensure` around the run (flock also drops on exit as a
  backstop).
- Keep it to the JSON/HTML/history/coverage-writing scope; a dry run
  (`--dry-run`, no artifact writes) need not lock.

Rejected: a bare PID file (stale-lock problem on crash — the very orphaning
scenario in `2026-07-09-orphaned-worker-processes-on-parent-kill.md`). flock is
kernel-released, so it degrades cleanly.

## Test Plan

- Unit: with the lock held (open the lock file + `flock LOCK_EX` in the test),
  a second `Runner#run` against the same `reports_dir` raises the framework
  error / exits `2`; a run against a different `reports_dir` proceeds.
- Unit: the lock is released after a normal run and after an exception (a
  subsequent run in the same dir succeeds).
- Regression: single runs and `--dry-run` are unaffected; full suite +
  `rake smoke:integration:all` stay green.
- Manual: start one run, start a second against the same `reports_dir` mid-flight
  → second aborts with the diagnostic instead of merging.

## Resolution (status corrected 2026-08-21)

Shipped in 0.3.0; this header was stale, which made the item look open during
the 0.5.0 backlog review.

- `lib/henitai/reports_directory_lock.rb` — `LOCK_FILENAME = ".henitai-run.lock"`,
  `flock(LOCK_EX | LOCK_NB)`, owner pid + start time written as JSON, and
  `ConcurrentRunError` carrying this ticket's exact message wording.
- `lib/henitai/runner.rb:56` wraps the whole pipeline in
  `ReportsDirectoryLock#synchronize`. The block form releases on both normal
  exit and exception, satisfying the `ensure` requirement.
- `lib/henitai/cli/clean_command.rb:19` takes the same lock, so `clean` cannot
  delete a live run's artifacts — beyond what this ticket asked for.
- The live-repro request for dead-owner diagnostics also shipped:
  `reports_directory_lock.rb:49-66` probes liveness with `Process.kill(0, pid)`
  (ESRCH ⇒ dead, EPERM ⇒ treated alive) and appends an `lsof` hint.
- Documented in `README.md:186-194`, `CHANGELOG.md` 0.3.0, and
  `docs/architecture/architecture.md:187,:202`.

Two deltas against the original sketch, both deliberate:

1. **`--wait` was never built.** Acquisition is `LOCK_NB` only, fail-fast. Split
   out as [`2026-08-21-reports-dir-lock-wait-flag.md`](2026-08-21-reports-dir-lock-wait-flag.md).
2. **The dry-run carve-out was decided the other way.** This ticket suggested a
   dry run "need not lock"; `runner.rb:53-56` takes the lock *before* the
   `@dry_run` branch, and `runner.rb:83-87` plus `README.md:186-194` state that
   every run including `--dry-run` locks, since the lock file may be a dry
   run's only artifact.

A third item surfaced later and is fixed separately: a child that survived its
parent inherited the parent's `flock` fd, pinning the lock open and making every
subsequent run fail with a `ConcurrentRunError` naming a dead pid. That is fork
hygiene rather than a locking defect — see
[`2026-07-09-orphaned-worker-processes-on-parent-kill.md`](2026-07-09-orphaned-worker-processes-on-parent-kill.md).
