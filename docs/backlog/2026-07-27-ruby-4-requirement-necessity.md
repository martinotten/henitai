# The Ruby >= 4.0 Requirement Is Not Technically Necessary

Status: backlog
Date: 2026-07-27
Severity: Medium
Source: 2026-07-27 experiment (release-0.4.0 review follow-up)

## Summary

`henitai.gemspec` declares `required_ruby_version = ">= 4.0.0"`, which locks the
gem out of every project on Ruby 3.x. Measured on Ruby 3.3.6: exactly **one**
Ruby 4.0 API is used — `Enumerable#rfind`, in three places — and it was
introduced by RuboCop's `Style/ReverseFind` cop under `TargetRubyVersion: 4.0`,
not by any design need. With that one call replaced by `reverse_each.find` and
the cop's target lowered, the entire suite, the linter, the type checker, and
both end-to-end smoke projects pass unchanged on 3.3.6.

## Evidence

Experiment: `git worktree` of `0c6d48a` on Ruby 3.3.6, gemspec relaxed to
`>= 3.3.0`, `LANG=C.UTF-8`. Total change needed: **5 lines across 5 files**
(gemspec constraint, `.rubocop.yml` target, 3 `rfind` call sites).

| Check | Result on Ruby 3.3.6 |
|---|---|
| `ruby -c` on all 247 tracked Ruby files | 0 syntax errors — no 4.0-only syntax anywhere |
| `bundle install` (existing `Gemfile.lock` versions) | 63 gems installed, no resolution conflict; no `RUBY VERSION` pin in the lockfile |
| `bundle exec rspec` (before the `rfind` fix) | 1672 examples, **5 failures — all one root cause** |
| `bundle exec rspec` (after `rfind` → `reverse_each.find`) | **1672 examples, 0 failures** |
| `bundle exec rubocop --parallel` (`TargetRubyVersion: 3.3`) | 256 files, **0 offenses** |
| `bundle exec steep check` | **No type error detected** |
| `bundle exec rake smoke:integration:all` | **all 3 green** — rspec (8 killed / 4 survived / 11 ignored), minitest (same), dogfood_rspec |

The single blocker, `Enumerable#rfind`:

- `lib/henitai/operators/return_value.rb:68`
- `lib/henitai/integration/rspec_process_runner.rb:35`
- `spec/henitai/operators/return_value_spec.rb:39` (spec-local helper)

All five failures were `NoMethodError: undefined method 'rfind' for an instance
of Array`. Note the feedback loop that put it there: with
`.rubocop.yml TargetRubyVersion: 4.0`, RuboCop **demands** `rfind` —
`Style/ReverseFind: Use rfind instead.` — so the linter actively converts
3.x-compatible code into 4.0-only code. Lowering the target silences it and the
codebase is clean either way.

Two findings that are *not* version issues, recorded so they are not
re-investigated:

- The encoding specs in `spec/henitai/integration/scenario_log_support_spec.rb`
  (`captures multibyte UTF-8 output …`, `captures a multibyte character split …`)
  fail on any Ruby when `Encoding.default_external` is US-ASCII, i.e. when no
  `LANG`/`LC_ALL` is set. They pass on 3.3.6 with `LANG=C.UTF-8`. Worth making
  the specs locale-independent (or asserting the locale in `spec_helper`) so a
  bare container does not produce a misleading red suite.
- The first of those failures also **hijacks the RSpec runner's stdout**: the
  example redirects `$stdout` into a child log file and the failure escapes
  before the redirect is restored, so the whole run ends with no summary and a
  bare exit 1. An `ensure`-based restore in the example (or `around` hook) would
  contain it.

## Options

1. **Relax to `>= 3.3.0`** (or `>= 3.4.0`) and add the version(s) to the CI
   matrix. Cost: the 3-line `rfind` change, `TargetRubyVersion` lowered, one
   extra CI leg. Benefit: usable by projects that are not yet on Ruby 4.
2. **Keep `>= 4.0.0` as a deliberate policy** ("we track the current Ruby"), but
   then say so explicitly — `README.md:46`, `AGENTS.md:45`,
   `docs/architecture/architecture.md:19,60` all state the requirement without a
   rationale, and there is no ADR for it. A one-paragraph ADR would stop this
   question from being re-asked.

Note the asymmetry that makes this more than cosmetic: henitai runs *inside* the
target project's Ruby process (mutants are injected via `define_method` in forked
children), so the constraint is not "we need 4.0 to build" — it is "your project
must be on 4.0 to be mutation-tested at all". Prism parses Ruby 4 syntax
regardless of the host Ruby, so the parser is not the limiting factor.

## Fix Plan

Depends on which option is chosen. For option 1:

1. Replace the three `rfind` calls with `reverse_each.find` (no behavior change;
   the full suite is green with this edit).
2. Set `.rubocop.yml TargetRubyVersion` to the new floor, so `Style/ReverseFind`
   stops demanding the 4.0-only form. Re-run `bundle exec rubocop --parallel`.
3. Set `spec.required_ruby_version` to the new floor in `henitai.gemspec`; update
   `README.md:46`, `AGENTS.md:5,45`, `CLAUDE.md`, and
   `docs/architecture/architecture.md:19,60,300` to match.
4. Add the floor version to the CI matrix in `.github/workflows/` (currently
   `ruby: ["4.0.2"]` only) — a single-version claim is not a supported-range
   claim. `spec/infra/gemspec_dependencies_spec.rb` and
   `spec/infra/ci_workflow_spec.rb` are the existing guards to extend.
5. Fix the locale-dependent encoding specs and the stdout-hijacking example noted
   above, independently of the version decision.

## Acceptance

- Either the floor is lowered and CI proves it on both versions, or an ADR
  records why 4.0 is required.
- No code path depends on a 4.0-only API without that dependency being
  intentional and documented.

## Related

- [[2026-07-27-review-index]] — the release-0.4.0 review round this came out of
- `docs/backlog/2026-06-16-review-gemspec-stale-uri.md` — prior gemspec/Ruby
  version mismatch cleanup
