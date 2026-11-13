# ADR-17: Version Support Lifecycle for Ruby and Rails

**Status:** Accepted — implementation pending
(`docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md`). Until it
lands, the ADR-16 floor (`>= 3.3.6`) and CI matrix stay in force.
**Date:** 2026-11-12
**Supersedes:** ADR-16

## Context

ADR-16 set the Ruby floor to 3.3.6 because that was the version measured
green, and required CI to exercise the floor. CI runs `3.3.6` and `4.0.2`
on Linux. Ruby 3.4 is not tested, no Rails application is exercised end to
end, and nothing reacts to new or end-of-life Ruby and Rails versions.

Henitai runs inside the target project's process, so the supported range
decides who can be mutation-tested at all. `mutant` publishes support
tables for Ruby 3.2–4.0 (runtime, syntax, mutations) and verifies Rails
7.2, 8.0 and 8.1 in CI. Henitai has no comparable statement for Rails and
no policy for when a version enters or leaves support.

Version facts (endoflife.date, 2026-11-12):

| Version | EOL |
|---|---|
| Ruby 3.2 | 2026-03-31 |
| Ruby 3.3 | 2027-03-31 |
| Ruby 3.4 | 2028-03-31 |
| Ruby 4.0 | 2029-03-31 |
| Rails 7.2 | 2026-08-09 |
| Rails 8.0 | 2026-11-07 |
| Rails 8.1 | 2027-10-10 |

Parsing uses `Prism::Translation::ParserCurrent` and mutants are rendered by
`unparser`, so a new Ruby version can break mutation generation, not only
the runtime.

## Decision

### 1. One lifecycle for Ruby and Rails versions

| State | When | Tested | Guaranteed | On failure |
|---|---|---|---|---|
| Supported | before upstream EOL | yes | yes | bug, fixed |
| Grace | from EOL until EOL + 1 year | yes | no | documented and dropped early, not fixed by default |
| Dropped | after EOL + 1 year, or an early drop | no | no | — |

Grace applies only to versions henitai supported before their EOL. Ruby 3.2
and Rails 7.2 are therefore not adopted.

Early drops are recorded in a committed policy file (version, date,
reason, issue), which the matrix generator honours so a dropped version is
not re-added automatically.

### 2. Ruby

- `required_ruby_version >= 3.3.0`; `.rubocop.yml` keeps
  `TargetRubyVersion: 3.3`.
- CI exercises the floor `3.3.0` and the latest patch release of every
  supported or grace minor. ADR-16's principle stays: the declared floor is
  always a version CI runs.
- Support is stated per Ruby version in three columns — runtime, syntax
  (version-specific syntax parses and round-trips), mutations (operators
  produce activatable mutants for it) — backed by a syntax corpus per
  version, not by claims.

### 3. Rails

- Supported Rails versions follow the lifecycle above; initially Rails 8.1
  (supported) and Rails 8.0 (grace).
- Ruby × Rails combinations follow the Rails gemspec's
  `required_ruby_version`, not a hand-kept list.
- Verification covers both integrations (RSpec, Minitest), both databases
  (SQLite, PostgreSQL) and every user-visible execution mode, with per-worker
  database isolation asserted directly.

### 4. Verification and documentation

- Verification runs on Linux in GitHub Actions. macOS is not claimed as
  verified.
- New stable releases, previews/RCs and heads (`ruby-head`, Rails `main`)
  enter a scheduled matrix automatically; prereleases are non-blocking.
  Failures and new minor/major releases open issues assigned to the
  maintainer.
- The documentation names the exact patch versions last verified. It is
  generated from a committed data file and updated by the scheduled run
  only when the version passed, so it never claims an untested version.

### 5. Dropping a version

Dropping a version under this lifecycle — at the end of grace or early
after a grace failure — needs no further ADR. For Ruby it raises
`required_ruby_version`, which is breaking for adopters: it ships in a new
minor release with a CHANGELOG entry, and the scheduled run opens a
reminder issue ahead of the grace end. This replaces ADR-16's rule that
raising the floor needs its own ADR.

## Consequences

- Projects on any Ruby 3.3 patch release can adopt henitai, and Rails users
  get a verified support statement comparable to `mutant`'s.
- Support follows upstream EOL automatically; nobody has to remember to add
  or retire versions, and a version that breaks during grace costs no fix.
- CI cost grows (Ruby matrix, Rails matrix, scheduled run). The size is kept
  down by testing every Rails version with all modes once and every Ruby
  version once with Rails, instead of the full cross product.
- The scheduled run commits to `main` (verified-version documentation) and
  must keep itself enabled under GitHub's 60-day inactivity rule.
- `spec/infra/supported_ruby_version_spec.rb` changes from pinning `3.3.6`
  to pinning the floor `3.3.0` against the generated matrix.
- Fewer execution modes mean a smaller matrix; the unification of the
  execution drivers
  (`docs/backlog/2026-11-12-unify-execution-paths-on-slot-scheduler.md`)
  halves the Rails modes to verify.

## Related Documents

- ADR-16 — the superseded floor decision and its measurement
- ADR-15 — fork-server execution model (one of the verified modes)
- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md` —
  implementation plan
- `henitai.gemspec`, `.github/workflows/ci.yml`,
  `spec/infra/supported_ruby_version_spec.rb`
