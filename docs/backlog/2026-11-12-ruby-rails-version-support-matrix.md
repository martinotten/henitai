# Ruby / Rails Version Support Matrix With Automatic New-Version Tracking

Status: proposed
Date: 2026-11-12
Severity: Medium (feature parity with `mutant`; adoption for Rails users)
Source: requirement intake 2026-11-12 — parity with mutant's published
support tables (Ruby 3.2–4.0 for runtime/syntax/mutations; Rails 7.2, 8.0,
8.1 verified in CI including parallel-worker database isolation on
PostgreSQL and SQLite).

## Summary

Henitai should state and continuously verify which Ruby and Rails versions
it supports, at least as rigorously as mutant does. Supported Ruby versions
are tested with every compatible supported Rails version, through both
test-framework integrations, both databases, and the parallel and
fork-server execution modes. New Ruby and Rails releases (stable,
preview/RC, and head) enter the matrix automatically; failures are filed as
GitHub issues assigned to the maintainer. EOL versions follow a one-year
grace policy.

## Current state (2026-11-12)

- `henitai.gemspec`: `required_ruby_version >= 3.3.6`; `.rubocop.yml`
  `TargetRubyVersion: 3.3`; README says "Requires Ruby 3.3.6+".
- `.github/workflows/ci.yml` tests only Ruby `3.3.6` and `4.0.2`, Linux
  only. Ruby 3.4 is not tested at all.
- Rails support exists in code (`Integration::RailsEnvironmentPreloader`,
  `PARALLEL_WORKERS=1` in `Integration::Base`/`Integration::Minitest`,
  `HENITAI_WORKER_SLOT` per worker slot in `SlotScheduler` from
  `2026-07-02-parallel-worker-resource-isolation-hooks.md`), but no Rails
  application is exercised end to end. The smoke fixtures
  (`spec/fixtures/integration_smoke/{rspec,minitest}`) are plain Ruby.
- There is no scheduled workflow and no automatic issue creation.
- Parsing uses `Prism::Translation::ParserCurrent`, i.e. the grammar of the
  running Ruby, and mutants are rendered through `unparser`. New syntax in a
  new Ruby version is therefore a risk for the *mutations* column, not only
  for the runtime column: `unparser` lagging behind a Ruby release silently
  breaks or skips mutants.

Version facts (endoflife.date, 2026-11-12):

| Version | EOL | Grace ends | Status under R0 |
|---|---|---|---|
| Ruby 3.3 (latest 3.3.13) | 2027-03-31 | 2028-03-31 | supported |
| Ruby 3.4 (latest 3.4.12) | 2028-03-31 | 2029-03-31 | supported |
| Ruby 4.0 (latest 4.0.9) | 2029-03-31 | 2030-03-31 | supported |
| Rails 8.0 (latest 8.0.5.2) | 2026-11-07 | 2027-11-07 | grace (tested, not guaranteed) |
| Rails 8.1 (latest 8.1.4.1) | 2027-10-10 | 2028-10-10 | supported |

Rails 8.0 and 8.1 both require Ruby >= 3.2, so all 8 Ruby × Rails pairs are
compatible. Ruby 3.2 and Rails 7.2 are in their EOL year but were never
supported by henitai; the grace policy applies only to versions henitai
supported before their EOL, so they are not added.

## Requirements

### R0 — Version lifecycle policy (Ruby and Rails alike)

1. **Supported:** the version is not EOL. It is tested and guaranteed;
   failures are bugs to fix.
2. **Grace (EOL + 1 year):** the version keeps being tested, but support is
   no longer guaranteed. A failure is not fixed by default; instead it is
   documented (changelog + support table), the version is removed from the
   matrix and dropped from support at that point.
3. **Dropped:** one year after EOL — or earlier per step 2 — the version is
   no longer tested and support is removed (README table; for Ruby also
   `required_ruby_version`, which needs a release).

A committed policy file (e.g. `config/support_matrix.yml` or
`.github/support-matrix.yml`) records explicit early drops (version, date,
reason, issue link). The matrix generator must honour it — otherwise the
generator would re-add a broken grace version on the next scheduled run.

### R1 — Ruby support

- Lower `required_ruby_version` to `>= 3.3.0` (from `3.3.6`); keep
  `TargetRubyVersion: 3.3`; update README and
  `spec/infra/supported_ruby_version_spec.rb`.
- This changes an accepted decision: ADR-16 ("Supported Ruby range starts
  at 3.3.6") chose 3.3.6 because 3.3.0 was never run. Its rationale still
  holds — the floor must be exercised — and CI will now exercise 3.3.0.
  ADR-17 (`docs/architecture/adr/ADR-17-version-support-lifecycle.md`)
  supersedes ADR-16 and records the R0 lifecycle policy.
- The Ruby matrix contains the floor `3.3.0` **plus the latest patch
  release of every supported or grace minor** (today: 3.3.13, 3.4.12,
  4.0.9).
- Publish a mutant-style support table in the README with three columns per
  Ruby version: **Runtime** (henitai runs), **Syntax** (all syntax of that
  version parses and round-trips), **Mutations** (operators produce valid,
  activatable mutants on that version's syntax), plus a lifecycle status
  (supported / grace).

### R2 — Rails support

- Initial scope: **Rails 8.0 (grace) and 8.1 (supported)**. Afterwards the
  set follows R0 automatically: new minors join, EOL minors move to grace,
  grace ends or a grace failure drops them.
- Ruby × Rails combinations are derived from compatibility (the Rails
  gemspec's `required_ruby_version` against the Ruby matrix), not hand
  maintained.
- README Rails table is generated from, or checked against, the same source
  of truth as the CI matrix (infra spec).

### R3 — Rails integration coverage

For every compatible (Ruby, Rails) pair, henitai runs end to end against a
real Rails application with all of:

- both integrations: RSpec (`rspec-rails`) and Minitest (Rails default);
- both databases: SQLite and PostgreSQL (service container);
- four execution modes, `jobs` × `fork_server`, because each is its own
  code path:

  | Mode | `jobs` | `fork_server` | Path under test |
  |---|---|---|---|
  | linear | 1 | off | `ExecutionEngine` linear path, per-mutant boot via `RailsEnvironmentPreloader` |
  | parallel | 2 | off | `ProcessWorkerRunner`/`SlotScheduler`, per-slot DB via `HENITAI_WORKER_SLOT` |
  | fork server linear | 1 | on | ADR-15 server, connections opened at server boot inherited by every mutant |
  | fork server parallel | 2 | on | `ForkServer::Runtime` in the scheduler, slot env passed in `run` after boot |

  The modes run sequentially in the same CI job, so the fourth mode costs
  run time, not an extra job.

  Four modes are needed only because there are two execution drivers today
  (a synchronous `run_mutant` path and the asynchronous `SlotScheduler`
  path), each with a fork-server variant. If the drivers are unified (see
  `2026-11-12-unify-execution-paths-on-slot-scheduler.md`, proposed),
  `jobs` becomes a pure concurrency number and the matrix shrinks to two
  modes: `fork_server` off and on, both with `jobs: 2`.

**Suspected defect to verify first:** README documents per-slot isolation as
`database: "myapp_test_#{ENV.fetch('HENITAI_WORKER_SLOT', '0')}"` in
`database.yml`. That file is evaluated when Rails boots. Without fork
server this is fine: `Integration::Minitest#run_in_child` boots Rails
(`RailsEnvironmentPreloader`) inside the forked child, after the slot env
is set. In fork-server mode the server boots once
(`preload_environment`), before any slot exists, and henitai has no
ActiveRecord reconnect after fork (`ChildBootstrap.after_fork!` does not
touch connections). Every mutant process might then share the server's
database and even its inherited connection. The isolation probe in the fork-server
parallel mode decides this; if confirmed it is a separate bug ticket (and a
README correction), not part of this item.

### R4 — Syntax / mutation corpus per Ruby version

A fixture corpus covering version-specific syntax (e.g. 3.4 `it` block
parameter, 4.0 additions, pattern matching, endless methods, anonymous
argument forwarding) is mutated on each Ruby version; the run must produce
mutants for it, activate them, and report no unexpected CompileError. This
backs the Syntax and Mutations columns with evidence instead of claims.

### R5 — Automatic new-version tracking

- A scheduled workflow (nightly) builds the matrix dynamically: Ruby and
  Rails cycles, latest patches and EOL dates from endoflife.date, Rails
  prereleases from the RubyGems API, honouring the R0 policy file.
- Additionally, **non-blocking**: Ruby previews / RCs and `ruby-head`, Rails
  RC/beta and Rails `main`.
- A failing combination opens a GitHub issue **assigned to the repository
  maintainer**, labelled (e.g. `compat`, `ruby-<v>`, `rails-<v>`, and
  `prerelease` or `grace` where applicable), with combination, failing job
  and log link.
- One open issue per combination (dedupe via a hidden marker): repeat
  failures comment on it, a green run closes it.
- A grace-version failure produces an issue whose action is the R0 drop
  (policy-file entry + docs), not a fix.
- The scheduled job also opens a reminder issue ahead of a grace period's
  end (e.g. 30 days before), since dropping a Ruby minor needs a gemspec
  change and a release.
- **Release issues:** the scheduled job compares the detected versions with
  the last known state and opens an issue (assigned to the maintainer) for
  every new Ruby or Rails **minor/major** release and every new prerelease
  cycle (first preview/RC of a version), because these need deliberate
  follow-up (policy file, README tables, `load_defaults`, fixture). New
  **patch** releases enter the matrix silently; they only produce an issue
  when they fail. The last known state lives in a committed data file or
  is derived from existing release issues (marker), not in the Actions
  cache.
- **Verified-versions commit (doubles as keepalive):** since the matrix
  always tests the latest patch of each minor, the supported-versions
  documentation names the exact patch versions last verified (e.g. "Ruby
  3.4.12, Rails 8.1.4.1, verified 2026-11-12"), generated from a committed
  data file. When a new patch release passes the nightly matrix, the nightly
  regenerates that file and the README tables and commits the change to
  `main` (branch is unprotected; with protection it would be an auto-merged
  PR). Only green versions are committed, so the docs never claim an
  untested version. Every Ruby or Rails patch release thereby produces a
  commit, which is repository activity for GitHub's 60-day rule — issues
  and comments are not (per third-party guides; GitHub does not define the
  term).
- **Keepalive backstop:** patch releases are frequent but not guaranteed
  within 60 days. The nightly additionally re-enables itself through the
  Actions API, and PR CI files an issue when the last nightly run is older
  than a few days.

## Matrix size and minimal test design

### Where henitai actually touches Rails

The dimensions are not equally risky. Henitai-specific Rails risk lives in:

1. Booting through `RailsEnvironmentPreloader` (Rails version).
2. Loading Rails' Minitest runner vs. `rspec-rails` (framework).
3. Disabling Rails' own `parallelize` via `PARALLEL_WORKERS=1` (framework).
4. Per-worker database isolation with `HENITAI_WORKER_SLOT` (DB × `jobs`).
5. ActiveRecord connections inherited across `fork`, worst in fork-server
   mode where the server process booted the app (DB × mode).
6. Coverage bootstrap and per-test coverage with Zeitwerk/eager loading.

Ruby version risk is mostly independent of Rails (parser, `unparser`,
`Coverage`, `fork`, `sqlite3`) and is caught by the unit suite, the plain
smoke projects and the R4 corpus on each Ruby — not by Rails jobs.

### Full cross product

4 Ruby × 2 Rails × 2 frameworks × 2 DBs × 4 modes = **128 runs** (64 after
execution-path unification). Too many as separate jobs, but most runs
share setup.

### Which interactions need full coverage

| Interaction | Henitai-specific risk | Coverage |
|---|---|---|
| framework × DB × mode | high: own code (preload, isolation, fork server, connections after fork) | complete |
| Rails × mode | medium: ActiveRecord fork/reconnect behaviour changes between Rails versions | complete per Rails version |
| Ruby × henitai | high: parser, `unparser`, `Coverage`, `fork` | every Ruby in the core job |
| Ruby × Rails | low: Rails' own compatibility promise, not henitai code | each Ruby once with Rails |
| Ruby × Rails × mode | very low | accepted gap |

Consequence: the full Ruby × Rails cross product is not needed. Every Rails
version gets the complete framework × DB × mode block once (on the newest
compatible Ruby); every Ruby version gets its core job plus one Rails smoke.

### Proposed tiers

Each Rails job covers one (Rails, framework, DB) cell on the newest
compatible Ruby and runs the four modes sequentially (one
`bundle install`, one app, four `henitai run`s) — 4 jobs per Rails
version.

- **PR CI (blocking), 8 jobs:**
  - Ruby core: 4 jobs (3.3.0, 3.3.13, 3.4.12, 4.0.9) — unit suite, plain
    smoke, R4 corpus, plus **one Rails smoke** (newest Rails, Minitest,
    SQLite, `jobs > 1`) inside the same job — "each Ruby once with Rails"
    at no extra job.
  - Rails: newest Rails × {RSpec, Minitest} × {SQLite, PG}, all four modes
    each = 4 jobs.
- **Nightly (scheduled), ~17 jobs:** PR set, plus 4 cells per further
  supported or grace Rails version (today 8.0), plus non-blocking
  prereleases: `ruby-head` core job and Rails `main` / RC × 4 cells.
- Full cross product (all Ruby × Rails pairs, ~40 jobs) only if a real
  Ruby × Rails defect ever slips through the reduced set.

### Minimal fixture that still guarantees the risk points

- **One committed Rails app** (`spec/fixtures/integration_smoke/rails`),
  not one app per Rails version and not generated in CI: the Gemfile pins
  `rails` from a `RAILS_VERSION` env var (or `github: rails/rails` for
  `main`); `database.yml` selects the adapter from an env var and appends
  `HENITAI_WORKER_SLOT` to the database name; the app contains both
  `spec/` and `test/`, and the run selects the integration. A new Rails
  minor usually needs no fixture change; when it does, that is exactly the
  issue we want.
- **Version-neutral by construction** — the single app must run on every
  Rails version in the matrix:
  - minimal hand-written config instead of full generator output (only
    `config/application.rb`, `boot.rb`, `environment.rb`,
    `environments/test.rb`, `database.yml`), no assets, mailers, jobs or
    credentials;
  - `config.load_defaults` set to the oldest Rails minor in the matrix (it
    is forward compatible, never backward), moved up when that minor drops;
  - no committed `Gemfile.lock` for the Rails app; instead one gemfile per
    Rails version (`gemfiles/rails_8_0.gemfile`, `rails_8_1.gemfile`,
    `rails_main.gemfile`, generated by the matrix generator or selected via
    `BUNDLE_GEMFILE`), so each version resolves its own dependencies;
  - version conditionals in the fixture are a smell: once one is needed,
    record it; if they accumulate (typically at a Rails major), split the
    fixture per major.
- **Fixture vs. henitai failure:** each Rails job first runs the app's own
  suite without henitai (`bin/rails test` / `rspec`). If that fails, the
  issue is labelled `fixture` (the app is incompatible with the new Rails),
  not `compat` (henitai is broken) — so automatic issues point at the right
  cause.
- **Minimal domain:** one ActiveRecord model with a validation, a scope and
  a plain method; tests that hit the database (create + query) so mutants
  are killed through DB-backed tests; one deliberate survivor.
- **Deterministic assertions** (no hoping for races):
  - expected mutants are Killed, the deliberate survivor Survives;
  - zero CompileError / RuntimeError / Timeout;
  - **isolation probe:** a test asserts that the connected database name
    carries the current `HENITAI_WORKER_SLOT` when `jobs > 1` — proves
    isolation directly instead of relying on cross-talk to show up;
  - **mode equivalence:** the killed/survived verdict set is identical
    across all four modes (same idea as
    `oracle:reuse`) — catches fork/connection bugs as verdict drift.
- Reuse `IntegrationSmoke::Project` assertions in
  `rakelib/integration_smoke.rake`; add a parameterised
  `smoke:integration:rails` task (framework/DB/modes via env).

## Proposed delivery order

1. **Ruby floor + Ruby matrix** (R1): gemspec, README, infra specs, CI
   matrix with 3.3.0 + latest patches. Small and independent.
2. **R4 syntax corpus** as an additional smoke project.
3. **Rails fixture app + `smoke:integration:rails`** (R3), first locally
   and in PR CI with the 4 Rails jobs. Depends on
   `2026-11-12-unify-execution-paths-on-slot-scheduler.md` (prioritized),
   so the fixture is built for two modes instead of four.
4. **Policy file + matrix generator** (R0/R2/R5) — a Ruby script tested in
   `spec/infra`, emitting the GitHub Actions matrix JSON; README tables
   checked against it.
5. **Nightly workflow + issue reporter** (R5) via `gh`, with dedupe,
   auto-close, assignment and grace-end reminders.

## Open questions

- None at intake time. Decided 2026-11-12: **Linux only** in GitHub CI (PR
  and scheduled). The README support tables state "verified on Linux";
  macOS is not claimed as CI-verified (it remains the maintainer's local
  development platform, without a guarantee).

## GitHub Actions limits (public repository; verify against current docs
## before implementation)

- Standard GitHub-hosted Linux runners are free with unlimited minutes for
  public repositories; a standard public Linux runner has 4 vCPUs and 16 GB
  RAM, enough for `jobs: 2` plus PostgreSQL.
- Free plan concurrency is 20 jobs: PR CI (8 jobs) and nightly (~17 jobs)
  each fit into a single wave; overlapping PR pushes and the nightly queue,
  they do not fail.
- At most 256 jobs per matrix, 6 h per job — far away from the planned
  sizes.
- Actions cache is 10 GB per repository; one bundler cache per
  Ruby × gemfile (~10 entries) fits.
- **Scheduled workflows in public repositories are disabled automatically
  after 60 days without repository activity.** A disabled nightly creates no
  issue, so the version tracking would fail silently. Mitigation: the
  nightly keeps itself alive (re-enable through the Actions API, which
  resets the counter), and the issue reporter also files an issue when the
  last nightly run is older than a few days (checked from PR CI).
- `schedule` triggers can be delayed or dropped under load, especially at
  full hours; use an odd minute and allow `workflow_dispatch` for manual
  runs.
- The issue reporter needs `permissions: issues: write`; the `GITHUB_TOKEN`
  limit of 1,000 API requests per hour per repository is not a concern.

## Acceptance criteria

- `required_ruby_version >= 3.3.0`; CI green on 3.3.0 and on the latest
  patch of each supported or grace Ruby minor.
- README contains Ruby (Runtime/Syntax/Mutations + lifecycle) and Rails
  support tables consistent with the generated matrix (infra spec).
- For every Rails version in the nightly matrix (on its newest compatible
  Ruby): RSpec and Minitest × SQLite and PostgreSQL pass in all four modes
  with the deterministic assertions above, including the isolation probe
  and mode equivalence.
- Every Ruby version in the matrix passes its core job including one Rails
  smoke.
- The same committed Rails app runs unchanged on every Rails version in the
  matrix; a fixture incompatibility is reported as `fixture`, not `compat`.
- A new stable Ruby or Rails release appears in the nightly matrix without a
  code change; an EOL version moves to grace and leaves the matrix after one
  year without a code change; a policy-file drop removes it immediately.
- A failing combination produces exactly one open issue, assigned to the
  maintainer, updated on repeat failures and closed when green; prerelease
  and grace failures are labelled as such and do not fail the blocking
  gate.

## Related

- `docs/backlog/2026-07-02-parallel-worker-resource-isolation-hooks.md`
  (`HENITAI_WORKER_SLOT`)
- `docs/architecture/adr/ADR-15-fork-server-execution-model.md`
- `docs/backlog/2026-07-08-review-send-integration-minitest-spec.md`
  (`RailsEnvironmentPreloader`)
- `rakelib/integration_smoke.rake`, `.github/workflows/ci.yml`
