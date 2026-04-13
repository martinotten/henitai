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

### Repo RuboCop Rules

- `Style/FrozenStringLiteralComment`: always add `# frozen_string_literal: true`.
- `Style/StringLiterals`: use double quotes.
- `Metrics/MethodLength`: keep methods at 15 lines or fewer.
- `Metrics/ClassLength`: keep classes at 200 lines or fewer.
- `Metrics/BlockLength`: `spec/**/*` and `*.gemspec` are excluded, but blocks should still stay compact.
- `RSpec/ExampleLength`: keep examples at 40 lines or fewer.
- `AllCops: NewCops: enable`: new cops are part of the contract; do not leave a fresh offense for later.
- `AllCops: Exclude`: RuboCop ignores `vendor/**/*`, `tmp/**/*`, and `.simplecov`.

### Default RuboCop Rules

- The list below is the operational subset we expect generated Ruby to satisfy.
- Treat RuboCop defaults as versioned. Re-check them with `bundle exec rubocop --show-cops` after dependency bumps.
- `Layout/LineLength`: keep lines under 120 characters; break long calls, arrays, hashes, and chains instead of squeezing them together.
- `Layout/ArgumentAlignment`: align multiline method calls with the first argument.
- `Layout/ArrayAlignment`: align multiline arrays with the first element.
- `Layout/HashAlignment`: keep multiline hashes consistently aligned.
- `Layout/DotPosition`: use leading dots for multiline chains.
- `Layout/SpaceAroundOperators`: put spaces around operators; keep exponent and rational literal spacing at RuboCop defaults.
- `Layout/SpaceAroundEqualsInParameterDefault`: use spaces around default parameter equals.
- `Layout/AccessModifierIndentation`: indent `private`, `protected`, and `public` inside classes.
- `Style/Documentation`: document non-namespace classes and modules in `lib`; `spec/**/*` is exempt.
- `Style/AccessModifierDeclarations`: group visibility declarations instead of repeating `private` around each method.
- `Style/For`: use `each`, not `for`.
- `Style/FormatString`: prefer `format(...)` over `sprintf` or `%`.
- `Style/GlobalVars`: avoid introducing global variables.
- `Style/SpecialGlobalVars`: if globals are unavoidable, use the English built-ins RuboCop expects, such as `$stdout`, `$stderr`, `$LOAD_PATH`, `$PROGRAM_NAME`, and `$CHILD_STATUS`.
- `Style/Lambda`: use the repo's default lambda style consistently.
- `Style/StabbyLambdaParentheses`: keep parentheses around stabby lambda arguments.
- `Style/NegatedUnless`: prefer positive conditions instead of negated `unless`.
- `Style/ModuleFunction`: avoid `extend self`; use `module_function` only for intentional utility modules.

### Bundler And Gemspec Rules

- Keep dependency entries sorted.
- `Bundler/OrderedGems`: sort Gemfile entries alphabetically.
- `Bundler/GemFilename`: use the `Gemfile` naming convention.
- `Bundler/DuplicatedGem` and `Bundler/DuplicatedGroup`: do not duplicate gem or group entries.
- `Gemspec/OrderedDependencies`: sort gemspec dependencies alphabetically.
- `Gemspec/RequiredRubyVersion`: keep `required_ruby_version` aligned with `TargetRubyVersion`.
- `Gemspec/RubyVersionGlobalsUsage`: do not use `RUBY_VERSION` in gemspecs.
- `Bundler/InsecureProtocolSource`: keep gem sources on HTTPS unless a documented exception exists.

## Useful Commands

- `bundle exec rspec`
- `bundle exec rubocop --parallel`
- `bundle exec steep check`
- `bundle exec henitai run`

When in doubt, choose the simplest change that satisfies the spec and stays
aligned with `CODE_PRINCIPLES.md`.

## Mutation Testing Framework Reference

Research about mutation testing `docs/research`

The following frameworks use apache or BSD licences and can be used as reference for implementation details, edge cases or test design. Do not copy tests, APIs or implementations 1:1.

https://github.com/sourcefrog/cargo-mutants.git
https://github.com/infection/infection.git
https://github.com/stryker-mutator/stryker-net.git
https://github.com/stryker-mutator/stryker-js.git

You can clone the repositories here `/tmp/mutation-test-frameworks` with depth 1 or use the cloned versions if available.

@RTK.md
