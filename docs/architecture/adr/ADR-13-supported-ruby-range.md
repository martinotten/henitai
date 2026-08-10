# ADR-13: Supported Ruby Range Starts at 3.3.6, Not 4.0

**Status:** Accepted
**Date:** 2026-08-01

## Context

`henitai.gemspec` declared `required_ruby_version = ">= 4.0.0"` from the
first release, and `README.md`, `AGENTS.md`, `CLAUDE.md` and the
architecture document all repeated the requirement without stating why.
No ADR recorded it, so the constraint read as a deliberate policy that
nobody could explain.

The constraint is unusually expensive for this gem. Henitai runs *inside*
the target project's Ruby process — mutants are injected via
`define_method` in forked children — so `required_ruby_version` does not
mean "we need 4.0 to build". It means "your project must be on 4.0 to be
mutation-tested at all". Every project still on Ruby 3.x was locked out,
which is most of them.

Measurement on Ruby 3.3.6 (worktree of `0c6d48a`, gemspec floor relaxed,
`LANG=C.UTF-8`) showed the requirement was almost entirely incidental:

| Check | Result on 3.3.6 |
|---|---|
| `ruby -c` over all tracked Ruby files | 0 syntax errors — no 4.0-only syntax |
| `bundle install` with the existing lockfile | resolves; no `RUBY VERSION` pin |
| `bundle exec rspec` before the fix | 5 failures, one root cause |
| `bundle exec rspec` after the fix | 0 failures |
| `bundle exec rubocop --parallel` (`TargetRubyVersion: 3.3`) | 0 offenses |
| `bundle exec steep check` | clean |
| `bundle exec rake smoke:integration:all` | all green |

The single blocker was `Enumerable#rfind`, at three call sites. Its
presence was itself an artifact of the constraint: with
`.rubocop.yml TargetRubyVersion: 4.0`, RuboCop's `Style/ReverseFind` cop
*demands* the 4.0-only form, so the linter was actively converting
3.x-compatible code into 4.0-only code. The codebase is clean under either
target.

## Decision

The supported range starts at **Ruby 3.3.6**.

- `required_ruby_version = ">= 3.3.6"` — the version actually measured
  green, rather than an untested `>= 3.3.0`.
- `.rubocop.yml` targets `3.3`, so the linter cannot reintroduce 4.0-only
  APIs.
- `Enumerable#rfind` is replaced by `reverse_each.find` everywhere.
- CI runs the floor (`3.3.6`) alongside `4.0.2`. A single-version matrix
  is not a supported-range claim; the floor has to be exercised to mean
  anything.
- `spec/infra/supported_ruby_version_spec.rb` pins the gemspec floor, the
  RuboCop target and the CI matrix to each other.

Development continues on 4.0.x (`.ruby-version` is unchanged): the floor
is a compatibility claim, not a toolchain downgrade.

## Consequences

- Projects on Ruby 3.3.6 and later can adopt henitai. This is the point of
  the change.
- Ruby 4.0-only APIs are no longer available in `lib/`. The guard spec and
  the RuboCop target make that a build failure rather than a runtime
  surprise for 3.3 users.
- CI cost roughly doubles for the `test` job (two matrix legs). This is
  the price of the compatibility claim being true.
- Raising the floor later is a breaking change for adopters and needs its
  own ADR.
- The floor is a patch-level version, which is unusual for a gem. It is
  deliberate: 3.3.6 is what was measured, and claiming `>= 3.3.0` would
  extend the promise to versions nothing has run against.

## Related Documents

- `henitai.gemspec` — the constraint itself
- `spec/infra/supported_ruby_version_spec.rb` — the drift guard
- `.github/workflows/ci.yml` — the matrix that exercises the floor
