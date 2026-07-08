# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Hen'i-tai (`henitai`) is an AST-based mutation-testing framework for Ruby 4.0+. It mutates source code (e.g. `>` -> `>=`, `true` -> `false`) and re-runs the test suite to measure whether tests actually catch the change. Output is Stryker-compatible JSON, consumable by Stryker Dashboard and `mutation-testing-elements` HTML reports.

`CODE_PRINCIPLES.md` is the authoritative source for coding rules (TDD, clean architecture, clean code). Follow it strictly; if a change conflicts with it or with `docs/architecture/architecture.md`, resolve the conflict before coding. `AGENTS.md` carries the same rules plus the full RuboCop default-cop checklist this repo is expected to satisfy.

RTK command usage: see `RTK.md`.

## Commands

```sh
bundle install

bundle exec rspec                                    # full suite
bundle exec rspec spec/henitai/runner_spec.rb         # one file
bundle exec rspec spec/henitai/runner_spec.rb:42      # one example at line 42

bundle exec rubocop --parallel                        # lint (must be clean before any commit)
bundle exec steep check                               # type check against sig/henitai.rbs

bundle exec henitai run                               # dogfood: mutation-test this repo itself
bundle exec henitai run --since origin/main           # diff-based, CI-friendly
bundle exec henitai run 'Henitai::Runner#run'         # single subject
bundle exec henitai run --survivors-from reports/mutation-report.json  # partial rerun
bundle exec henitai clean                             # remove stale generated report artifacts

bundle exec rake smoke:integration:all                # run both integration smoke projects
bundle exec rake smoke:integration:rspec              # spec/fixtures/integration_smoke/rspec only
bundle exec rake smoke:integration:minitest           # spec/fixtures/integration_smoke/minitest only
bundle exec rake smoke:integration:dogfood_rspec
```

Enable the repo git hook (runs rubocop, rspec, and the smoke suite pre-commit):

```sh
git config core.hooksPath .githooks
```

`henitai run` exit codes: `0` mutation score meets the low threshold, `1` does not meet it, `2` framework error. With `--strict-exit-codes` (opt-in, additive): `3` one or more mutants timed out, `4` runtime/compile errors present; precedence `2` > `3` > `4` > `1` > `0`. The timeout code is informational — a run can pass its threshold and still exit `3`.

## Architecture

Full design doc: `docs/architecture/architecture.md` (arc42 structure); decisions in `docs/architecture/adr/`. Canonical language for docs/code/reports is English.

### Pipeline

```text
CLI -> Orchestrator (Runner)
        -> Source Analyzer       (git diff -> changed subjects)
        -> Test Inventory        (coverage bootstrap, prioritization)
        -> Mutant Generator      (AST walk -> candidate mutants)
        -> Execution Engine      (forked, isolated test runs)
        -> Analysis and Scoring  (status classification, MS/MSI)
        -> Reporter               (terminal, JSON, HTML, dashboard)
```

`lib/henitai/runner.rb` documents this as a 6-gate execution order (Gate 0 = coverage bootstrap ... Gate 5 = reporting); `docs/architecture/architecture.md` §8.2 frames the same pipeline as a cost-reduction view (incremental analysis -> arid-node filtering -> selective mutation -> stillborn filtering -> stratified sampling).

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

`lib/henitai/eager_load.rb` is a standalone entry point with no in-process coverage and is excluded from `includes` in `.henitai.yml`.

### Execution model

- Source parsing uses Prism's translation layer (real AST, not regex). `RubyVM::AbstractSyntaxTree` is for inspection only, not the mutation backend.
- Mutants run via `Module#define_method` injection inside **forked worker processes** — process isolation is the default and required model, not thread-only parallelism.
- `ExecutionEngine`/`ProcessWorkerRunner` use a Thread+Queue worker pool (`config.jobs`, default `1`) where each worker forks a child process per mutant: threads coordinate the queue, forked processes provide test isolation.
- Survived mutants are retried up to `config.max_flaky_retries` (default 3) before being classified as survived; a warning is emitted if >5% of mutants needed a retry.
- Coverage is a required gate, checked before subject resolution: if existing coverage doesn't cover the configured sources, the configured test suite is run once to bootstrap it; if still unusable, `Henitai::CoverageError` aborts the run.

### Status model and scoring

Statuses: `Killed`, `Survived`, `NoCoverage`, `Timeout`, `CompileError`, `RuntimeError`, `Ignored`, `Equivalent`, `Pending`.

```text
MS  = (killed + timeout) / (total - ignored - no_coverage - compile_error - equivalent)
MSI = killed / total
```

`Equivalent` is an internal status, serialized as `Ignored` in the external Stryker schema (`EquivalenceDetector` only flags AST-provable cases like `x + 0`, `x * 1` — deliberately conservative to avoid false positives). `MS` and `MSI` must always be reported together.

### Operators

Canonical operator names are public API; don't alias them. Light set (default, `mutation.operators: light`): `ArithmeticOperator`, `EqualityOperator`, `LogicalOperator`, `BooleanLiteral`, `ConditionalExpression`, `StringLiteral`, `ReturnValue`. Full set adds `SafeNavigation`, `RangeLiteral`, `HashLiteral`, `PatternMatch`, `ArrayDeclaration`, `BlockStatement`, `MethodExpression`, `AssignmentExpression`, `UnaryOperator`, `UpdateOperator`, `RegexMutator`, `MethodChainUnwrap`. This repo's own `.henitai.yml` dogfoods with `operators: full`.

`# henitai:disable` magic comments skip mutation at the call site (trailing comment = line-scoped, standalone comment directly above a `def` = method-scoped); handled by `MutationSkipDirectives` inside `StaticFilter`, matches are reported as `Ignored`, not dropped.

Arid-node filtering (intentionally skipped locations) covers logger/debug calls, `binding.pry`/`byebug`, frozen constants, memoization (`@var ||= ...`), RSpec DSL helpers, and `is_a?`/`respond_to?`/`kind_of?`. The `@var ||= ...` exclusion is deliberate even though `||=` is a valid `UpdateOperator`/`AssignmentExpression` target elsewhere — `UpdateOperator` can still emit the `&&=` side of that pair.

### Persistence and reports

- `MutantHistoryStore` persists mutant status history in `reports/mutation-history.sqlite3`, keyed by a stable SHA256 of expression/operator/description/location/signature (survives line-number drift). Used for latent-mutant tracking, kept separate from the pass/fail model.
- Reports default to `reports/` (override via `reports_dir`): `mutation-report.json` (canonical, Stryker schema), `mutation-report.html`, `mutation-history.json` (trend export), `henitai_per_test.json` (per-test coverage, propagated to forked children via `HENITAI_REPORTS_DIR`).
- Live terminal progress is separate from captured child stdout/stderr, written to `reports/mutation-logs/` and only shown on failure or with `--all-logs`/`--verbose`.
- Dashboard reporter uploads to Stryker Dashboard when `STRYKER_DASHBOARD_API_KEY` + project + version are configured; otherwise silently skipped.

## Testing this repo

- `spec/henitai/` unit-tests each `lib/henitai/*` module 1:1; `spec/henitai/operators/`, `spec/henitai/integration/`, `spec/henitai/mutant/`, `spec/henitai/reporter/` mirror the corresponding `lib` subdirs.
- `spec/infra/` checks repo-level invariants (CI workflow, gemspec deps, pre-commit hook, steep scope, config schema, smoke-project wiring) rather than `lib` behavior.
- `spec/fixtures/integration_smoke/{rspec,minitest}` are tiny real RSpec/Minitest apps that depend on `henitai` via a local path; `bundle exec rake smoke:integration:*` runs `henitai` against them end-to-end to verify both test-framework integrations actually work, not just unit-level mocks.
- `Steepfile` only type-checks a subset of `lib` entry points (`henitai.rb`, `configuration.rb`, `subject.rb`, `mutant.rb`, `operator.rb`, `integration.rb`, `reporter.rb`, `result.rb`, `runner.rb`) against `sig/henitai.rbs` — `spec/infra/steep_scope_spec.rb` guards this list.
