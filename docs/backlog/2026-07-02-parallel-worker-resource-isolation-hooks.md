# Parallel-Worker Resource-Isolation Hooks

Status: backlog
Date: 2026-07-02
Severity: Medium
Source: feature-parity comparison against `mutant`

## Summary

`mutant` ships a documented hooks system (`docs/hooks.md`) so users can run
arbitrary setup/teardown code around each parallel worker's lifecycle —
most commonly to give each worker its own isolated database (Rails
PostgreSQL/SQLite examples are documented). Henitai forks a child process
per mutant (`config.jobs > 1` via `ProcessWorkerRunner`/`SlotScheduler`) but
has no equivalent extension point: any shared external resource (a test
database, Redis, a shared tmp directory) is the user's problem to isolate,
with no hook to plug isolation logic into henitai's own worker lifecycle.

## Problem

`ProcessWorkerRunner`/`SlotScheduler` (`lib/henitai/process_worker_runner.rb`,
`lib/henitai/slot_scheduler.rb`) own the fork/spawn/reap lifecycle for each
worker slot, but expose no callback points. A project whose test suite
touches a shared database (the common case for any Rails/ActiveRecord
project, and plenty of non-Rails ones) cannot safely set `config.jobs > 1`
today without external, unsupported workarounds — parallel workers would
race on the same DB connection/transaction state.

This directly limits how much of the parallelism henitai already built
(`SlotScheduler`, `ProcessWakeup`, fork-per-mutant isolation) is actually
usable: the isolation is only *process* isolation (each mutant's `define_
method` injection is contained to its own child), not *resource*
isolation (a DB the child connects to is still shared with every other
child).

## Proposed Behavior

A `hooks:` config entry (`.henitai.yml`) naming one or more Ruby files that
are `require`d and can register callbacks for defined lifecycle events —
at minimum:

- `before_fork(worker_index:)` — runs in the parent, once per worker slot,
  before that worker's first spawn (e.g. create worker-specific DB/schema).
- `after_fork(worker_index:)` — runs in the child immediately after fork,
  before mutant activation (e.g. reconnect ActiveRecord to the
  worker-specific DB).
- `after_run(worker_index:)` — parent-side, once the worker pool shuts down
  (e.g. drop the worker-specific DB).

Mirrors `mutant`'s documented hook events closely enough that existing
Rails hook scripts written for `mutant` would need only minor adaptation,
not a rewrite.

## Suggested Interface

```yaml
# .henitai.yml
hooks:
  - config/henitai_hooks.rb
```

```ruby
# config/henitai_hooks.rb
Henitai::Hooks.before_fork do |worker_index:|
  `createdb myapp_test_worker_#{worker_index}`
end

Henitai::Hooks.after_fork do |worker_index:|
  ActiveRecord::Base.establish_connection(database: "myapp_test_worker_#{worker_index}")
end
```

## Non-Goals

- Not shipping Rails-specific DB-isolation logic in henitai core — hooks
  are a generic extension point; any Rails-specific helper (if it comes
  later) belongs in a separate integration gem, not `lib/henitai/`.
- Not changing the default (`config.jobs: 1`) behavior — hooks are inert
  and unused unless a project both sets `jobs > 1` and configures `hooks:`.
- Not solving in-process (thread-based, `jobs: 1` linear path) resource
  contention — that path already runs sequentially with no concurrent
  resource access.

## Open Questions

- Hook registration API shape — module-level `Henitai::Hooks.before_fork`
  (mutant-like, global registration) vs. a config-injected object passed
  into `ProcessWorkerRunner` (more testable, more idiomatic for this
  codebase's existing DI patterns like `DashboardMetadataProvider`'s
  injectable `env:`/`git_executor:`). Lean toward DI given this repo's
  established preference for avoiding global mutable state (see the
  `env:`/`git_executor:` and `color_enabled:` injection seams already used
  in `lib/henitai/reporter.rb`), but needs a design spike.
- Where exactly `after_fork` fires relative to `Mutant::Activator.activate!`
  — must run before mutant activation so a worker-specific DB connection
  exists before any test executes against it.
- **Fork-per-mutant vs. fork-per-worker model mismatch.** Henitai forks a
  fresh child *per mutant execution*, not a long-lived worker process per
  slot — `SlotScheduler` spawns at two separate sites: the initial spawn
  and the flaky-retry respawn. `before_fork(worker_index:)`/`after_fork`
  framed as "once per worker slot" implies a stable slot→resource mapping
  (e.g. slot 2 always owns DB `myapp_test_worker_2`) that the scheduler
  would need to track and keep stable across every mutant a slot processes
  *and* across flaky retries — otherwise a retry respawn skips
  `after_fork` and runs against no (or the wrong) isolated resource. This
  needs a real design decision: hook once per slot-lifetime (cheaper, but
  requires slot-index stability the scheduler doesn't currently guarantee
  as a public concept) vs. once per spawn/respawn (simpler mental model,
  matches the two actual fork sites, but re-provisions resources more
  often than mutant's per-worker Rails DB examples assume).

## Implementation Notes

- `lib/henitai/slot_scheduler.rb` owns both fork points — the initial
  spawn and the flaky-retry respawn are two separate call sites, each
  invoking `integration.spawn_mutant`; hook invocation must cover both or
  isolation silently leaks on any retried mutant.
- `lib/henitai/configuration.rb` needs a new `hooks` key, validated by
  `configuration_validator.rb`. Note: `includes`/`excludes` are only
  type-checked as string arrays today
  (`ConfigurationValidator::Rules.validate_includes` →
  `Scalars.validate_string_array`) — there is no existing file-existence
  check to copy; `hooks` would introduce the first one (or follow the same
  type-only precedent and let the `require` fail at load time).
