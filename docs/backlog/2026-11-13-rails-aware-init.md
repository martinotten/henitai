# Rails-Aware `henitai init`

Status: proposed
Date: 2026-11-13
Severity: Medium (first-run experience for Rails adopters)
Source: requirement intake 2026-11-12, follow-up to the Rails support work
(ADR-17).

## Summary

`henitai init` writes a fixed template. For a Rails application that
template mutates nothing useful and misconfigures several options. `init`
should detect the project shape and write a configuration that works on the
first `henitai run`.

## Current state (`lib/henitai/cli/init_command.rb`)

- `includes: [lib]` only — in a Rails app, `app/` (models, services,
  controllers) is not mutated at all.
- Integration: asks only "Use the default RSpec integration?"; Minitest is
  never offered, although Rails defaults to Minitest.
- `timeout: 10.0` is written explicitly, which disables auto-calibrated
  timeouts (`calibration_enabled?` is false when a timeout is configured) —
  a fixed 10 s is too short for many Rails suites and too long for small
  ones.
- `sampling.ratio: 0.05` is the default for every new project: a first run
  mutates 5 % of mutants without saying so prominently.
- The schema comment points to `./assets/schema/henitai.schema.json`, which
  exists only inside the henitai repository.
- An existing `.henitai.yml` is overwritten without confirmation.

## Requirements

1. **Detection:** Rails (`config/application.rb`), RSpec (`spec/` +
   `rspec-core` in the lockfile) vs. Minitest (`test/`), plain gem
   (`lib/` + `*.gemspec`).
2. **Rails template:**
   - `includes: [app, lib]`, excluding `app/views`, `app/assets`,
     `app/javascript`, `db/`, `config/`;
   - integration from detection; `test_excludes` for system/feature tests
     (browser-driven, slow) as a commented suggestion;
   - `jobs` and `fork_server` with comments, and the per-slot
     `database.yml` snippet printed after creation (only once the
     fork-server isolation item guarantees it for `fork_server`).
3. **All templates:** no explicit `timeout` (calibration on); sampling
   off by default or clearly commented; schema reference that works outside
   the repository (published URL or omitted).
4. **Safety:** refuse to overwrite an existing file unless `--force`.
5. **Non-interactive:** `--integration rspec|minitest` and detection
   results work without a TTY (CI, agents).
6. README "Getting started" shows the Rails path.

## Acceptance criteria

- On the Rails fixture of the version-matrix item, `henitai init` followed
  by `henitai run` produces mutants in `app/models` without manual edits,
  for RSpec and for Minitest.
- On this repository, `init` (into a temp path) produces the plain-gem
  template.
- Existing configuration is never overwritten silently.

## Related

- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md` (fixture)
- `docs/backlog/2026-11-13-fork-server-worker-db-isolation.md`
- `lib/henitai/cli/init_command.rb`, `assets/schema/henitai.schema.json`
