# AGENTS.md

## Repository Intent

Hen'i-tai is a Ruby 4 mutation-testing framework.

`CODE_PRINCIPLES.md` is the authoritative source for coding rules in this
repository. Follow it strictly. If a requested change conflicts with that file
or with the architecture docs, stop and resolve the conflict before coding.

## Non-Negotiables

- Use test-driven development: write a failing spec first, implement the
  smallest change needed to make it pass, then refactor.
- Preserve clean architecture boundaries: keep domain rules isolated, keep
  framework and infrastructure concerns at the edges, and make dependencies
  point inward.
- Keep code clean and simple: prefer small methods, descriptive names, explicit
  dependencies, and the simplest design that satisfies the spec.
- Treat tests as part of the design: keep them fast, independent, repeatable,
  readable, and focused on one behavior per example when practical.

## Worktree And Documentation

- Read `README.md`, `docs/architecture/architecture.md`, `docs/plan/implementation_plan.md`, and the relevant ADRs
  before changing behavior.
- Update or add specs whenever behavior changes.
- Update documentation when the public API, CLI, configuration, or architecture
  changes.
- Do not overwrite unrelated work in the repository.

## Test Workflow

1. Reproduce or characterize the behavior with a spec.
2. Add or update the smallest failing test.
3. Implement the smallest code change that makes the test pass.
4. Refactor while keeping the suite green.
5. Run the relevant specs first, then the full suite for broader changes.

## Ruby And Style

- Target Ruby 4.0.x.
- Follow the repo RuboCop rules in `.rubocop.yml`.
- Use double-quoted strings and frozen string literals.
- Keep lines short and methods small.
- Prefer root-cause fixes over defensive complexity.

## Useful Commands

- `bundle exec rspec`
- `bundle exec rubocop --parallel`
- `bundle exec steep check`
- `bundle exec henitai run`

When in doubt, choose the simplest change that satisfies the spec and stays
aligned with `CODE_PRINCIPLES.md`.
