# Verify the Dependency Ranges the Gemspec Promises

Status: proposed
Date: 2026-11-13
Severity: Medium (adopters resolve versions henitai never ran against)
Source: requirement intake 2026-11-12; follow-up to ADR-17 (version support
lifecycle) — the same "claim only what CI exercises" principle applied to
henitai's own runtime dependencies.

## Summary

Henitai runs inside the target project's bundle, so the adopter's lockfile
decides which versions of henitai's dependencies are loaded. The gemspec
allows wide ranges, but CI only exercises the single version in henitai's
own `Gemfile.lock`. Exercise the lower and upper ends of every range, and
track new major versions automatically.

## Current state (2026-11-13)

| Dependency | Gemspec range | Locked / tested | Untested ends |
|---|---|---|---|
| `minitest` | `>= 5.25, < 7` | 5.27.0 | 5.25, all of 6.x |
| `prism` | `~> 1.5` | 1.9.0 | 1.5–1.8 |
| `simplecov` | `>= 0.22, < 2` | 1.2.0 | 0.22.x (1.x allowed since #50) |
| `sqlite3` | `>= 2.9.5, < 3` | 2.9.6 | 2.9.5 |
| `unparser` | `~> 0.6` | 0.9.0 | 0.6–0.8 |
| `rspec-core` | not a gemspec dependency; project's own | 3.13.6 | every other 3.x the user brings |

`unparser` and `prism` are the riskiest: they decide what parses and how
mutants are rendered, and `~> 0.6` spans several minors of a pre-1.0 gem.

## Requirements

1. **Floor and latest bundles:** two additional gemfiles resolve every
   dependency at its gemspec floor (`gemfiles/deps_floor.gemfile`) and at
   the newest allowed version (`gemfiles/deps_latest.gemfile`). Each runs the
   unit suite and the smoke projects (and the R4 syntax corpus of the
   version-matrix item) on the newest Ruby; the floor bundle also on the
   Ruby floor.
2. **PR CI** runs the floor bundle (cheap, catches use of newer APIs);
   **nightly** runs both, plus RSpec 3.x floor (`rspec-core` lowest version
   the RSpec integration supports — to be determined and documented).
3. **New majors:** the nightly also resolves the next major of each
   dependency outside the range (e.g. `minitest` 7, `sqlite3` 3,
   `unparser` 1.0) when released, non-blocking; a pass opens an issue to
   widen the range, a failure an issue describing the break.
4. **Fix the ranges** where the floor bundle fails: either support the
   floor or raise it in the gemspec (patch release, CHANGELOG).
5. Issues follow the version-matrix item (assigned to the maintainer, one
   per dependency/version, closed when green).

## Acceptance criteria

- Floor and latest bundles are green, or the gemspec ranges have been
  narrowed to what is green.
- `spec/infra` guards that every gemspec dependency appears in both
  gemfiles with its range ends.
- A new major release of a dependency produces an issue without a code
  change.

## Related

- `docs/architecture/adr/ADR-17-version-support-lifecycle.md`
- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md`
  (matrix generator, nightly, issue reporter — reuse, don't duplicate)
- `henitai.gemspec`, `Gemfile.lock`
