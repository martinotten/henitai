# Opt-in `--wait` for the Reports-Directory Lock

Status: backlog
Date: 2026-08-21
Severity: Low (ergonomics; the fail-fast path is correct today)
Source: split out of
[`2026-07-09-concurrent-runs-clobber-shared-reports-dir.md`](2026-07-09-concurrent-runs-clobber-shared-reports-dir.md)
when that ticket's status was corrected to done — the lock shipped in 0.3.0, but
this one item of its sketch did not

## Summary

`ReportsDirectoryLock` acquires with `flock(LOCK_EX | LOCK_NB)` and fails fast,
raising `ConcurrentRunError` (CLI exit `2`). The original ticket floated "consider
an opt-in `--wait` to block instead". It was never built.

## Problem

A CI pipeline or a script that runs henitai twice against the same `reports_dir`
must either serialise the invocations itself or retry on exit `2`. Blocking is
occasionally the more natural default for that caller — but only when explicitly
asked for, since silently waiting on a lock is worse than failing when the other
holder is a hung run.

## Fix Sketch

- `--wait [SECONDS]` on `henitai run`, defined in `lib/henitai/cli/run_options.rb`
  as one `add_*_option` method, wired through `Options#add_run_flag_options`.
- `ReportsDirectoryLock#synchronize(wait:)` retries `LOCK_NB` on an interval up
  to the deadline rather than switching to a blocking `LOCK_EX`. Polling keeps
  the existing dead-owner diagnostics reachable while waiting, and keeps Ctrl-C
  responsive.
- On timeout, raise the same `ConcurrentRunError` with the waited duration
  appended, so exit `2` and the message shape do not change for existing callers.
- Default stays fail-fast. Do not make waiting implicit.

## Non-Goals

- No blocking `flock(LOCK_EX)` without a deadline — an indefinite wait behind a
  hung parent is exactly the failure this would be sold as fixing.
- No cross-run queueing or fairness guarantees.

## Test Plan

- Unit: with the lock held, `--wait 0` behaves exactly as today; a `--wait` that
  outlasts the holder acquires successfully; a `--wait` that expires raises
  `ConcurrentRunError` with the duration in the message.
- The real-fork variant belongs in
  `spec/henitai/reports_directory_lock_process_spec.rb` (fork-using specs must be
  named `*_process_spec.rb`); use `Dir.mktmpdir`, never the checkout.
- CLI: `spec/henitai/cli_spec.rb` for flag parsing and precedence.
