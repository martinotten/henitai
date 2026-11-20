# Per-Worker Database Isolation in Fork-Server Mode

Status: proposed
Date: 2026-11-13
Severity: High if confirmed (verdicts of Rails suites can be wrong with
`fork_server` + `jobs > 1`; blocks `fork_server` as a default)
Source: requirement intake 2026-11-12 while designing the Rails matrix
(`2026-11-12-ruby-rails-version-support-matrix.md`, "Suspected defect");
deferred stage 3 of `2026-07-02-parallel-worker-resource-isolation-hooks.md`.

## Summary

Henitai guarantees that every mutant process under `fork_server` talks to
the database of its own worker slot over a connection it opened itself — not
to the database the server booted with, and never over a connection
inherited from the server.

## Suspected defect (code reading, not reproduced)

- README ("Worker slots") tells users to isolate per slot in
  `database.yml`:
  `database: "myapp_test_#{ENV.fetch('HENITAI_WORKER_SLOT', '0')}"`.
  `database.yml` is evaluated when Rails boots.
- Without fork server this works: `Integration::Minitest#run_in_child` boots
  Rails (`RailsEnvironmentPreloader`) inside the forked child, after
  `SlotScheduler` has set `HENITAI_WORKER_SLOT`. The same holds for RSpec
  children that load `rails_helper`.
- With fork server, the server boots once (`preload_environment`) before
  any slot exists. `ForkServer::MutantRunner#spawn_env` passes the slot only
  as an env var to the served child. `ChildBootstrap.after_fork!` does not
  touch database connections. So every served child would use the server's
  database name (slot `0` or none), and may reuse a connection object the
  server opened during boot.
- ADR-15 lists inherited connections as a known negative ("the same caveat
  as the Rails preloader") but no mechanism handles it.

Rails ≥ 7.1 discards inherited connection pools after fork
(`ActiveSupport::ForkTracker`), which may prevent socket sharing, but the
reconnect still uses the configuration resolved at boot, i.e. the wrong
database. To verify.

## Requirements

1. **Reproduce first:** a Rails fixture (the one from the version matrix
   item, or a minimal one) with `fork_server: true`, `jobs: 2`, PostgreSQL
   and SQLite; a test asserts that the connected database name carries the
   current `HENITAI_WORKER_SLOT`. Expected today: fails. If it passes,
   close this item and document why.
2. **Isolation in served children:** after fork, before tests run, a served
   child re-establishes ActiveRecord connections with the configuration
   resolved *for its slot*. Options to decide in planning:
   - built-in: henitai detects ActiveRecord in the server and, in the child,
     re-resolves `database.yml` with the slot env and calls
     `establish_connection` (framework knowledge in an integration
     adapter, not in the core);
   - hook: a documented `after_fork` hook (Ruby file or config entry) run in
     every mutant child, with a Rails default recipe;
   - env var only (Infection's `TEST_TOKEN` style) is insufficient here,
     because the configuration is already resolved.
3. **No inherited connections:** the server disconnects or the child
   discards every pool inherited from boot before use (also for
   non-ActiveRecord resources the hook can cover, e.g. Redis).
4. **Same guarantee for control runs and fallback children** (per-mutant
   boot already gets it by booting after the slot is set).
5. README "Worker slots" states what is guaranteed in each mode.

## Acceptance criteria

- The isolation probe passes for RSpec and Minitest × SQLite and PostgreSQL
  with `fork_server` on and `jobs: 2`.
- Verdicts are identical with `fork_server` off and on for the fixture
  (mode equivalence, as in the matrix item).
- No connection object created in the server is used in a served child
  (asserted via the connection's object id / backend pid for PostgreSQL).

## Architecture notes

- Rails/ActiveRecord knowledge belongs in an integration-side adapter
  (outer layer), not in `ForkServer` or `SlotScheduler`.
- "No Parallel Implementations" (AGENTS.md): the after-fork step must be the
  same code for served children, per-mutant boot children and control runs;
  do not add a fork-server-only copy.
- If a hook mechanism is chosen, it needs an ADR (user-visible option) with
  an Execution paths section.

## Related

- `docs/architecture/adr/ADR-15-fork-server-execution-model.md`
- `docs/backlog/2026-07-02-parallel-worker-resource-isolation-hooks.md`
- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md`
- `lib/henitai/fork_server/mutant_runner.rb`,
  `lib/henitai/integration/child_bootstrap.rb`,
  `lib/henitai/integration/rails_environment_preloader.rb`
