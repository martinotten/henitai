# AGENTS.md

This is the canonical repository guidance file. `CLAUDE.md` is a symlink to
this file so all coding agents use the same instructions.

## Repository Intent

Hen'i-tai (`henitai`) is an AST-based mutation-testing framework for Ruby
3.3.6+. It mutates source code (for example, `>` to `>=` and `true` to
`false`) and reruns the test suite to measure whether tests catch the change.
Its output is Stryker-compatible JSON, consumable by Stryker Dashboard and
`mutation-testing-elements` HTML reports.

`CODE_PRINCIPLES.md` is the authoritative source for coding rules: TDD, clean
architecture, and clean code. Follow it strictly. If a requested change
conflicts with that file or with `docs/architecture/architecture.md`, stop and
resolve the conflict before coding.

Log mistakes in `MISTAKES.md`, including what happened, the root cause, and how
to prevent a recurrence.

RTK command usage is documented in `RTK.md`; follow the RTK instructions below
for command execution.

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

- Read `README.md`, `docs/architecture/architecture.md`,
  `docs/plans/implementation_plan.md`, and the relevant ADRs before changing
  behavior.
- Update or add specs whenever behavior changes.
- Update documentation when the public API, CLI, configuration, or architecture
  changes.
- Do not overwrite unrelated work in the repository.
- In the devcontainer, `/workspaces` itself is not writable. For temporary
  isolated review worktrees, use a plain temp path such as
  `/private/tmp/henitai-worktrees/<name>` instead of a docker-mounted folder.
- Canonical language for documentation, code, and reports is English.

## Test Workflow

1. Reproduce or characterize the behavior with a spec.
2. Add or update the smallest failing test.
3. Implement the smallest code change that makes the test pass.
4. Refactor while keeping the suite green.
5. Run the relevant specs first, then the full suite for broader changes.

## Commands

```sh
bundle install

bundle exec rspec                                    # full suite
bundle exec rspec spec/henitai/runner_spec.rb         # one file
bundle exec rspec spec/henitai/runner_spec.rb:42      # one example at line 42

bundle exec ruby bin/verify-process-free-specs
bundle exec rubocop --parallel                        # lint (clean before commit)
bundle exec steep check                               # type check against sig/henitai.rbs

bundle exec henitai run                               # dogfood this repository
bundle exec henitai run --since origin/main           # diff-based, CI-friendly
bundle exec henitai run 'Henitai::Runner#run'         # single subject
bundle exec henitai run --survivors-from reports/mutation-report.json
bundle exec henitai clean                             # remove stale reports

bundle exec rake smoke:integration:all
bundle exec rake smoke:integration:rspec
bundle exec rake smoke:integration:minitest
bundle exec rake smoke:integration:dogfood_rspec
```

Enable the repository git hook, which runs RuboCop, RSpec, and the smoke suite
before commits:

```sh
git config core.hooksPath .githooks
```

`henitai run` exit codes are `0` when the mutation score meets the low
threshold, `1` when it does not, and `2` for a framework error. With optional
`--strict-exit-codes`, the additional codes are `3` for one or more timed-out
mutants and `4` for runtime or compile errors. Precedence is `2` > `3` > `4` >
`1` > `0`. The timeout code is informational: a run can pass its threshold and
still exit `3`.

## Architecture

The full design is in `docs/architecture/architecture.md` (arc42 structure);
decisions are in `docs/architecture/adr/`.

### Pipeline

```text
CLI -> Orchestrator (Runner)
        -> Source Analyzer       (git diff -> changed subjects)
        -> Test Inventory        (coverage bootstrap, prioritization)
        -> Mutant Generator      (AST walk -> candidate mutants)
        -> Execution Engine      (forked, isolated test runs)
        -> Analysis and Scoring  (status classification, MS/MSI)
        -> Reporter              (terminal, JSON, HTML, dashboard)
```

`lib/henitai/runner.rb` documents this as a six-gate execution order (Gate 0
is coverage bootstrap and Gate 5 is reporting). Section 8.2 of the architecture
document presents the same pipeline as a cost-reduction view: incremental
analysis, arid-node filtering, selective mutation, stillborn filtering, and
stratified sampling.

### Key modules (`lib/henitai/`)

| Concern | Files |
|---|---|
| CLI / config | `cli.rb`, `configuration.rb`, `configuration_validator.rb` |
| Subject resolution | `subject.rb`, `subject_resolver.rb`, `git_diff_analyzer.rb` |
| Mutant generation | `operator.rb`, `operators.rb`, `operators/*`, `mutant_generator.rb`, `mutant.rb`, `mutant/activator.rb` |
| Filtering | `arid_node_filter.rb`, `static_filter.rb`, `mutation_skip_directives.rb`, `stillborn_filter.rb`, `syntax_validator.rb`, `equivalence_detector.rb` |
| Coverage | `coverage_bootstrapper.rb`, `coverage_report_reader.rb`, `coverage_formatter.rb`, `per_test_coverage_collector.rb`, `per_test_coverage_selector.rb` |
| Execution | `execution_engine.rb`, `process_worker_runner.rb`, `slot_scheduler.rb`, `process_wakeup.rb` |
| Survivor reruns | `survivor_loader.rb`, `survivor_selector.rb`, `survivor_rerun_strategy.rb`, `survivor_activation_cache.rb`, `survivor_test_filter.rb` |
| Results / history | `result.rb`, `scenario_execution_result.rb`, `mutant_history_store.rb` (SQLite), `mutant_identity.rb` |
| Reporting | `reporter.rb` (terminal/JSON/HTML/dashboard) |
| Test-framework integration | `integration.rb`, `integration/*`, `minitest_simplecov.rb`, `minitest_coverage_hook.rb`, `minitest_coverage_reporter.rb`, `rspec_coverage_formatter.rb` |

`lib/henitai/eager_load.rb` is a standalone entry point with no in-process
coverage and is excluded from `includes` in `.henitai.yml`.

### Execution model

- Source parsing uses Prism's translation layer (a real AST, not regex).
  `RubyVM::AbstractSyntaxTree` is for inspection only, not the mutation
  backend.
- Mutants run through `Module#define_method` injection inside forked worker
  processes. Process isolation is the required default model, not thread-only
  parallelism.
- `ExecutionEngine` and `ProcessWorkerRunner` use a Thread+Queue worker pool
  (`config.jobs`, default `1`). Each worker forks a child process per mutant;
  threads coordinate the queue and forked processes provide test isolation.
- Survived mutants are retried up to `config.max_flaky_retries` (default `3`)
  before being classified as survived. A warning is emitted if more than `5%`
  of mutants needed a retry.
- Coverage is a required gate before subject resolution. If existing coverage
  does not cover configured sources, the configured test suite runs once to
  bootstrap it. If coverage remains unusable, `Henitai::CoverageError` aborts
  the run.

### Status model and scoring

Statuses are `Killed`, `Survived`, `NoCoverage`, `Timeout`, `CompileError`,
`RuntimeError`, `Ignored`, `Equivalent`, and `Pending`.

```text
MS  = (killed + timeout) / (total - ignored - no_coverage - compile_error - equivalent)
MSI = killed / total
```

`Equivalent` is an internal status serialized as `Ignored` in the external
Stryker schema. `EquivalenceDetector` only flags AST-provable cases such as
`x + 0` and `x * 1`; this is deliberately conservative to avoid false
positives. `MS` and `MSI` must always be reported together.

### Operators

Canonical operator names are public API; do not alias them. The light set
(default, `mutation.operators: light`) contains `ArithmeticOperator`,
`EqualityOperator`, `LogicalOperator`, `BooleanLiteral`,
`ConditionalExpression`, `StringLiteral`, and `ReturnValue`.

The full set adds `SafeNavigation`, `RangeLiteral`, `HashLiteral`,
`PatternMatch`, `ArrayDeclaration`, `BlockStatement`, `MethodExpression`,
`AssignmentExpression`, `UnaryOperator`, `UpdateOperator`, `RegexMutator`, and
`MethodChainUnwrap`. The hard set adds the usually unkillable
`EqualityIdentityOperator` and `HashKeyType` on top of full (ADR-12). This
repository's own `.henitai.yml` dogfoods with `operators: light`, so hard- and
full-set operators do not fire on a plain `bundle exec henitai run` here — pass
`--operators full` (or `hard`) to reproduce anything involving them.

The `# henitai:disable` magic comment skips mutation at the call site. A
trailing comment is line-scoped; a standalone comment directly above a `def`
is method-scoped. `MutationSkipDirectives` handles this inside `StaticFilter`;
matches are reported as `Ignored`, not dropped.

Arid-node filtering intentionally skips logger/debug calls, `binding.pry` and
`byebug`, frozen constants, memoization (`@var ||= ...`), RSpec DSL helpers,
and `is_a?`/`respond_to?`/`kind_of?`. The `@var ||= ...` exclusion is
deliberate even though `||=` is a valid `UpdateOperator`/
`AssignmentExpression` target elsewhere; `UpdateOperator` can still emit the
`&&=` side of that pair.

### Persistence and reports

- `MutantHistoryStore` persists status history in
  `reports/mutation-history.sqlite3`, keyed by a stable SHA256 of expression,
  operator, description, location, and signature. It survives line-number
  drift and supports latent-mutant tracking separately from the pass/fail model.
- Reports default to `reports/` and can be overridden with `reports_dir`:
  `mutation-report.json` (canonical Stryker schema), `mutation-report.html`,
  `mutation-history.json` (trend export), and `henitai_per_test.json` (per-test
  coverage propagated to forked children through `HENITAI_REPORTS_DIR`).
- Live terminal progress is separate from captured child stdout/stderr. Child
  logs are written to `reports/mutation-logs/` and shown only on failure or
  with `--all-logs`/`--verbose`.
- The dashboard reporter uploads to Stryker Dashboard when
  `STRYKER_DASHBOARD_API_KEY`, project, and version are configured; otherwise
  it is silently skipped.

## Testing This Repository

- `spec/henitai/` unit-tests each `lib/henitai/*` module 1:1.
  `spec/henitai/operators/`, `spec/henitai/integration/`,
  `spec/henitai/mutant/`, and `spec/henitai/reporter/` mirror corresponding
  `lib` subdirectories.
- `spec/infra/` checks repository-level invariants such as CI workflow, gemspec
  dependencies, the pre-commit hook, Steep scope, configuration schema, and
  smoke-project wiring rather than `lib` behavior.
- `spec/fixtures/integration_smoke/{rspec,minitest}` are small real
  RSpec/Minitest applications depending on `henitai` through a local path.
  `bundle exec rake smoke:integration:*` runs `henitai` against them end to end
  to verify both test-framework integrations, not just unit-level mocks.
- `Steepfile` type-checks a subset of `lib` entry points
  (`henitai.rb`, `configuration.rb`, `subject.rb`, `mutant.rb`, `operator.rb`,
  `integration.rb`, `reporter.rb`, `result.rb`, `runner.rb`) against
  `sig/henitai.rbs`. `spec/infra/steep_scope_spec.rb` guards this list.

### Do Not Reach Private Methods From Specs

`spec/infra/private_method_reach_spec.rb` budgets every use of `send`,
`__send__`, `instance_variable_get` and `instance_variable_set` in the spec
tree. It is a ratchet: a budget may only go down, a spec that beats its budget
fails until the number is lowered in the same commit, and a file with no budget
may not reach private methods at all.

When you need to test behavior that is currently private, **extract a public
collaborator** — do not simply rewrite the example to drive the public facade,
and do not widen visibility. The precedent is
`docs/backlog/2026-07-08-review-send-integration-minitest-spec.md`: extracting
`MinitestSuiteCommand`, `MinitestTestRunner`, `MinitestLoadPath` and
`RailsEnvironmentPreloader` took `Henitai::Integration::Minitest` from
MS 72.83% / MSI 43.05% to MS 100% / MSI 91.87%. Because this repository scores
mutation coverage against itself, a pure public-API rewrite usually *loses*
coverage — the assertions get further from the logic they constrain.

Capture the host's MS/MSI before an extraction and re-measure host plus new
collaborator afterwards; the sum must not fall. If it does, the extraction left
an untested seam.

## Ruby And Style

- Target Ruby 3.3.6+ (`.rubocop.yml` TargetRubyVersion 3.3); the repository
  itself develops on Ruby 4.0.x.
- Follow the repository RuboCop rules in `.rubocop.yml`.
- Use double-quoted strings and frozen string literals.
- Keep lines short and methods small.
- Prefer root-cause fixes over defensive complexity.

### Repo RuboCop Rules

- `Style/FrozenStringLiteralComment`: always add
  `# frozen_string_literal: true`.
- `Style/StringLiterals`: use double quotes.
- `Metrics/MethodLength`: keep methods at 15 lines or fewer.
- `Metrics/ClassLength`: keep classes at 200 lines or fewer.
- `Metrics/BlockLength`: `spec/**/*` and `*.gemspec` are excluded, but blocks
  should still stay compact.
- `RSpec/ExampleLength`: keep examples at 40 lines or fewer.
- `AllCops: NewCops: enable`: new cops are part of the contract; do not leave a
  fresh offense for later.
- `AllCops: Exclude`: RuboCop ignores `vendor/**/*`, `tmp/**/*`, and
  `.simplecov`.

### Default RuboCop Rules

- The following is the operational subset expected for generated Ruby.
- Treat RuboCop defaults as versioned. Re-check them with
  `bundle exec rubocop --show-cops` after dependency bumps.
- `Layout/LineLength`: keep lines under 120 characters; break long calls,
  arrays, hashes, and chains instead of squeezing them together.
- `Layout/ArgumentAlignment`: align multiline method calls with the first
  argument.
- `Layout/ArrayAlignment`: align multiline arrays with the first element.
- `Layout/HashAlignment`: keep multiline hashes consistently aligned.
- `Layout/DotPosition`: use leading dots for multiline chains.
- `Layout/SpaceAroundOperators`: put spaces around operators; keep exponent and
  rational literal spacing at RuboCop defaults.
- `Layout/SpaceAroundEqualsInParameterDefault`: use spaces around equals in
  parameter defaults.
- `Layout/AccessModifierIndentation`: indent `private`, `protected`, and
  `public` inside classes.
- `Style/Documentation`: document non-namespace classes and modules in `lib`;
  `spec/**/*` is exempt.
- `Style/AccessModifierDeclarations`: group visibility declarations instead of
  repeating `private` around each method.
- `Style/For`: use `each`, not `for`.
- `Style/FormatString`: prefer `format(...)` over `sprintf` or `%`.
- `Style/GlobalVars`: avoid introducing global variables.
- `Style/SpecialGlobalVars`: if globals are unavoidable, use the English
  built-ins RuboCop expects, such as `$stdout`, `$stderr`, `$LOAD_PATH`,
  `$PROGRAM_NAME`, and `$CHILD_STATUS`.
- `Style/Lambda`: use the repository's default lambda style consistently.
- `Style/StabbyLambdaParentheses`: keep parentheses around stabby lambda
  arguments.
- `Style/NegatedUnless`: prefer positive conditions instead of negated
  `unless`.
- `Style/ModuleFunction`: avoid `extend self`; use `module_function` only for
  intentional utility modules.

### Bundler And Gemspec Rules

- Keep dependency entries sorted.
- `Bundler/OrderedGems`: sort Gemfile entries alphabetically.
- `Bundler/GemFilename`: use the `Gemfile` naming convention.
- `Bundler/DuplicatedGem` and `Bundler/DuplicatedGroup`: do not duplicate gem
  or group entries.
- `Gemspec/OrderedDependencies`: sort gemspec dependencies alphabetically.
- `Gemspec/RequiredRubyVersion`: keep `required_ruby_version` aligned with
  `TargetRubyVersion`.
- `Gemspec/RubyVersionGlobalsUsage`: do not use `RUBY_VERSION` in gemspecs.
- `Bundler/InsecureProtocolSource`: keep gem sources on HTTPS unless a
  documented exception exists.

When in doubt, choose the simplest change that satisfies the spec and stays
aligned with `CODE_PRINCIPLES.md`.

## Mutation Testing Framework Reference

Research about mutation testing is in `docs/research`.

The following Apache- or BSD-licensed frameworks may be used as references for
implementation details, edge cases, or test design. Do not copy tests, APIs, or
implementations 1:1.

- https://github.com/sourcefrog/cargo-mutants.git
- https://github.com/infection/infection.git
- https://github.com/stryker-mutator/stryker-net.git
- https://github.com/stryker-mutator/stryker-js.git

They can be cloned with depth 1 into `/tmp/mutation-test-frameworks` if needed.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses
it. If not, it passes through unchanged. This means RTK is always safe to use.

Even in command chains, prefix each command:

```bash
# Wrong
git add . && git commit -m "msg" && git push

# Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)

```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file
rtk tsc                 # TypeScript errors grouped by file/code
rtk lint                # ESLint/Biome violations grouped
rtk prettier --check    # Files needing format only
rtk next build          # Next.js build with route metrics
```

### Test (60-99% savings)

```bash
rtk cargo test          # Cargo test failures only
rtk go test              # Go test failures only
rtk jest                # Jest failures only
rtk vitest              # Vitest failures only
rtk playwright test     # Playwright failures only
rtk pytest              # Python test failures only
rtk rake test            # Ruby test failures only
rtk rspec                # RSpec test failures only
rtk test <cmd>            # Generic test wrapper - failures only
```

### Git (59-80% savings)

```bash
rtk git status           # Compact status
rtk git log              # Compact log
rtk git diff             # Compact diff
rtk git show             # Compact show
rtk git add              # Ultra-compact confirmation
rtk git commit           # Ultra-compact confirmation
rtk git push             # Ultra-compact confirmation
rtk git pull             # Ultra-compact confirmation
rtk git branch           # Compact branch list
rtk git fetch            # Compact fetch
rtk git stash            # Compact stash
rtk git worktree         # Compact worktree
```

Git passthrough works for all subcommands, even those not listed above.

### GitHub (26-87% savings)

```bash
rtk gh pr view <num>     # Compact PR view
rtk gh pr checks         # Compact PR checks
rtk gh run list          # Compact workflow runs
rtk gh issue list        # Compact issue list
rtk gh api               # Compact API responses
```

### JavaScript/TypeScript Tooling (70-90% savings)

```bash
rtk pnpm list            # Compact dependency tree
rtk pnpm outdated        # Compact outdated packages
rtk pnpm install         # Compact install output
rtk npm run <script>     # Compact npm script output
rtk npx <cmd>            # Compact npx command output
rtk prisma               # Compact Prisma output
rtk uv run <cmd>         # Compact uv project command output
```

### Files & Search (60-75% savings)

```bash
rtk ls <path>            # Tree format, compact
rtk read <file>          # Code reading with filtering
rtk grep <pattern>       # Search grouped by file
rtk find <pattern>       # Find grouped by directory
```

Format flags `-c`, `-l`, `-L`, `-o`, and `-Z` run raw with `rtk grep`.

### Analysis & Debug (70-90% savings)

```bash
rtk err <cmd>             # Filter errors only
rtk log <file>            # Deduplicated logs with counts
rtk json <file>           # JSON structure without values
rtk deps                  # Dependency overview
rtk env                   # Environment variables compact
rtk summary <cmd>         # Smart command summary
rtk diff                  # Ultra-compact diffs
```

### Infrastructure (85% savings)

```bash
rtk docker ps             # Compact container list
rtk docker images         # Compact image list
rtk docker logs <c>       # Deduplicated logs
rtk kubectl get           # Compact resource list
rtk kubectl logs          # Deduplicated pod logs
```

### Network (65-70% savings)

```bash
rtk curl <url>            # Compact HTTP responses
rtk wget <url>            # Compact download output
```

### Meta Commands

```bash
rtk gain                  # View token savings statistics
rtk gain --history        # View command history with savings
rtk discover              # Analyze sessions for missed RTK usage
rtk proxy <cmd>           # Run a command without filtering
rtk init                  # Add RTK instructions to CLAUDE.md
rtk init --global         # Add RTK to ~/.claude/CLAUDE.md
```

Overall average savings are typically 60-90% on common development operations.

<!-- /rtk-instructions -->
