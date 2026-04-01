# Hen'i-tai 変異体

**Pronunciation:** *hen-i-tai* (へんいたい) — three syllables, stress on first: **HEN**-i-tai.
Not *heh-ni-tai*. The kanji 変異体 means "mutant" (lit. "changed-form body").

A Ruby 4 mutation testing framework

[![CI](https://github.com/martinotten/henitai/actions/workflows/ci.yml/badge.svg)](https://github.com/martinotten/henitai/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/henitai.svg)](https://badge.fury.io/rb/henitai)

---

## What is mutation testing?

Mutation testing answers the question that code coverage cannot: **does your test suite actually verify the behaviour of your code?**

A mutation testing tool makes small, systematic changes — *mutants* — to your source code (e.g. replacing `>` with `>=`, removing a `return` statement, flipping a boolean) and then runs your tests. A mutant that causes at least one test to fail is *killed*. A mutant that passes all tests is *survived* — evidence that your tests are not covering that behaviour.

The ratio of killed mutants to total mutants is the **Mutation Score** (MS). A high mutation score is a stronger quality signal than line or branch coverage.

## Why henitai?

Henitai adopts the [mutation-testing-report-schema](https://github.com/stryker-mutator/mutation-testing-elements/tree/master/packages/report-schema) as its native output format. This means you get the Stryker Dashboard, interactive HTML reports, and badges for free — without any additional tooling.

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
  max_mutants_per_line: 1
  sampling:
    ratio: 0.05
    strategy: stratified

thresholds:
  high: 80
  low: 60
```

Henitai warns on unknown config keys and aborts with `Henitai::ConfigurationError`
when a value is invalid.

CLI flags override the corresponding values from `.henitai.yml`.

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

## Stryker Dashboard integration

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

## Development

```sh
git clone https://github.com/martinotten/henitai
cd henitai
bundle install
bundle exec rspec        # run tests
bundle exec rubocop      # lint
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

Research basis: [`docs/research/`](docs/research/) — summaries of 39 academic papers on mutation testing (1992–2025).

## Name

**変異体** (*hen'i-tai*) is the Japanese word for *mutant* — a direct conceptual counterpart to the Ruby `mutant` gem, with an open license and Ruby 4 as its native platform.

## License

[MIT License](LICENSE) — © 2026 Martin Otten
