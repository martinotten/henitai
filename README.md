# hen’itai

変異体 (へんいたい, hen’itai)
Pronunciation: he-n-i-ta-i (4 morae; no stress accent)
Meaning: mutant, mutated organism, or variant entity


A Ruby mutation testing framework

[![CI](https://github.com/martinotten/henitai/actions/workflows/ci.yml/badge.svg)](https://github.com/martinotten/henitai/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/henitai.svg)](https://badge.fury.io/rb/henitai)

---

## Maturaty

- This is alpha software, there will be bugs
- Henitai tests itself
- Stryker Dashboard support is untested
- Minitest support is untested
- Lots of code has been carefully crafted by AI agents, not everything has been reviewed by humans (yet)

## What is mutation testing?

Mutation testing answers the question that code coverage cannot: **does your test suite actually verify the behaviour of your code?**

A mutation testing tool makes small, systematic changes — *mutants* — to your source code (e.g. replacing `>` with `>=`, removing a `return` statement, flipping a boolean) and then runs your tests. A mutant that causes at least one test to fail is *killed*. A mutant that passes all tests is *survived* — evidence that your tests are not covering that behaviour.

The ratio of killed mutants to total mutants is the **Mutation Score** (MS). A high mutation score is a strong quality signal.

## Installation

Add to your `Gemfile`:

```ruby
gem "henitai", group: :development
```

Or install globally:

```sh
gem install henitai
```

**Requires Ruby 4.0.2+**

## Quick start

```sh
# Run mutation testing on the entire project
bundle exec henitai run

# Run only on subjects changed since main (CI-friendly)
bundle exec henitai run --since origin/main

# Run on a specific subject pattern
bundle exec henitai run 'MyClass#my_method'
bundle exec henitai run 'MyNamespace*'
```

Configuration lives in `.henitai.yml`:

```yaml
# yaml-language-server: $schema=./assets/schema/henitai.schema.json
integration:
  name: rspec

includes:
  - lib

mutation:
  operators: light   # light | full
  timeout: 10.0
  max_flaky_retries: 3
  sampling:
    ratio: 0.05
    strategy: stratified
reports_dir: reports

thresholds:
  high: 80
  low: 60
```

Henitai warns on unknown config keys and aborts with `Henitai::ConfigurationError`
when a value is invalid.

CLI flags override the corresponding values from `.henitai.yml`.

Before mutation testing starts, Henitai checks whether the current coverage data
covers the configured source files. If not, Henitai runs the configured test
suite once to bootstrap a usable coverage baseline. If coverage is still
unavailable for the current sources, `henitai run` aborts with
`Henitai::CoverageError`.

Surviving mutants are retried up to `mutation.max_flaky_retries` times before
they are classified as survivors. The default retry budget is 3.

Per-test coverage reporting is currently wired through the RSpec child runner.
Minitest integration reuses the same selection and execution flow, but does not
yet enable the per-test coverage formatter.

Henitai currently defaults to linear mutant execution. Set `jobs` in
`.henitai.yml` or pass `--jobs N` to opt into parallel mutant execution.

By default, Henitai keeps child test output out of the live terminal. Each
baseline or mutant run writes captured stdout/stderr to `reports/mutation-logs/`
and the terminal only shows progress plus a concise summary. Pass
`--all-logs` (or `--verbose`) to print every captured child log.

`henitai version` prints the installed version. `henitai run` exits with `0`
when the mutation score meets the low threshold, `1` when it does not, and `2`
for framework errors.

The repository ships a JSON Schema at [`assets/schema/henitai.schema.json`](/workspaces/henitai/assets/schema/henitai.schema.json) for editor autocompletion.

## Operator sets

**Light** (default) — high-signal, low-noise operators covering the majority of real-world defects:

- `ArithmeticOperator` — `+` ↔ `-`, `*` ↔ `/`
- `EqualityOperator` — `==` ↔ `!=`, `>` ↔ `<`, etc.
- `LogicalOperator` — `&&` ↔ `||`
- `BooleanLiteral` — `true` ↔ `false`, `!expr`
- `ConditionalExpression` — remove branch bodies
- `StringLiteral` — empty string replacement
- `ReturnValue` — mutate return expressions

**Full** — adds lower-signal operators:

- `ArrayDeclaration`, `HashLiteral`, `RangeLiteral`
- `SafeNavigation` — `&.` → `.`
- `PatternMatch` — case/in arm removal
- `BlockStatement` — remove blocks
- `MethodExpression` — remove calls
- `AssignmentExpression` — mutate compound assignment

## Stryker Dashboard integration (untested)

```yaml
# .henitai.yml
reporters:
  - terminal
  - html
  - json
  - dashboard

dashboard:
  project: "github.com/your-org/your-repo"
  base_url: "https://dashboard.stryker-mutator.io"
```

Set `STRYKER_DASHBOARD_API_KEY` in your CI environment to publish reports.

JSON reports are written to `reports/mutation-report.json` by default. Set
`reports_dir` to change the output directory.

## Development

```sh
git clone https://github.com/martinotten/henitai
cd henitai
bundle install
bundle exec rspec        # run tests
bundle exec rubocop      # lint
bundle exec henitai clean # remove stale generated report artifacts
bundle exec henitai run  # dogfood
```

A Dev Container configuration is included (`.devcontainer/`) for VS Code with the official `ruby:4.0.2-alpine` image and the Codex CLI preinstalled.

## Architecture

See [`docs/architecture/architecture.md`](docs/architecture/architecture.md) for the full design document, including:

- Phase-Gate pipeline (5 gates)
- AST-based operator implementation
- Fork isolation model
- Stryker JSON schema integration
- Architecture decisions in [`docs/architecture/adr/`](docs/architecture/adr/)
- Three-phase roadmap

## License

[MIT License](LICENSE) — © 2026 Martin Otten
