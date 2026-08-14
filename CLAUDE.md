# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Hen'i-tai (`henitai`) is an AST-based mutation-testing framework for Ruby 3.3.6+. It mutates source code (e.g. `>` -> `>=`, `true` -> `false`) and re-runs the test suite to measure whether tests actually catch the change. Output is Stryker-compatible JSON, consumable by Stryker Dashboard and `mutation-testing-elements` HTML reports.

`CODE_PRINCIPLES.md` is the authoritative source for coding rules (TDD, clean architecture, clean code). Follow it strictly; if a change conflicts with it or with `docs/architecture/architecture.md`, resolve the conflict before coding. `AGENTS.md` carries the same rules plus the full RuboCop default-cop checklist this repo is expected to satisfy.

RTK command usage: see `RTK.md`.

In the devcontainer, `/workspaces` itself is not writable. For temporary isolated review worktrees, use a plain temp path such as `/private/tmp/henitai-worktrees/<name>` instead of a docker-mounted folder.

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

Canonical operator names are public API; don't alias them. Light set (default, `mutation.operators: light`): `ArithmeticOperator`, `EqualityOperator`, `LogicalOperator`, `BooleanLiteral`, `ConditionalExpression`, `StringLiteral`, `ReturnValue`. Full set adds `SafeNavigation`, `RangeLiteral`, `HashLiteral`, `PatternMatch`, `ArrayDeclaration`, `BlockStatement`, `MethodExpression`, `AssignmentExpression`, `UnaryOperator`, `UpdateOperator`, `RegexMutator`, `MethodChainUnwrap`. Hard set adds the usually-unkillable `EqualityIdentityOperator` and `HashKeyType` on top of full (ADR-12). This repo's own `.henitai.yml` dogfoods with `operators: full`.

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

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
rtk uv run <cmd>        # Compact uv project command output
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->