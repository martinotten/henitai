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
- Henitai tests itself and other projects
- It might break with a release
- If you need a mature solution for mutation testing in ruby, take a look at the [https://github.com/mbj/mutant](Mutant gem)

## What is mutation testing?

Mutation testing answers the question that code coverage cannot: **does your test suite actually verify the behaviour of your code?**

A mutation testing tool makes small, systematic changes — *mutants* — to your source code (e.g. replacing `>` with `>=`, removing a `return` statement, flipping a boolean) and then runs your tests. A mutant that causes at least one test to fail is *killed*. A mutant that passes all tests is *survived* — evidence that your tests are not covering that behaviour.

The ratio of killed mutants to total mutants is the **Mutation Score** (MS). A high mutation score is a strong quality signal.

As mutation testing modifies your code you make sure that your tests cannot have any unintended side-effects.

## Installation

Add to your `Gemfile`:

```ruby
gem "henitai", group: :development
```

Or install globally:

```sh
gem install henitai
```

**Requires Ruby 4.0.0+**

## Quick start

```sh
# Run mutation testing on the entire project
bundle exec henitai run

# Run only on subjects changed since main (CI-friendly). Includes uncommitted
# working-tree changes; changed test files select the sources they cover.
bundle exec henitai run --since origin/main

# Run on a specific subject pattern
bundle exec henitai run 'MyClass#my_method'
bundle exec henitai run 'MyNamespace*'

# Re-run only survivors from a prior mutation report
bundle exec henitai run --survivors-from reports/mutation-report.json
```

Configuration lives in `.henitai.yml`:

```yaml
# yaml-language-server: $schema=./assets/schema/henitai.schema.json
integration:
  name: rspec

includes:
  - lib

excludes:
  - lib/henitai/eager_load.rb   # standalone entry points with no in-process coverage

test_excludes:
  - spec/end_to_end/*_spec.rb   # never select these files for individual mutants

mutation:
  operators: light   # light | full
  timeout: 10.0
  max_flaky_retries: 3
  max_log_bytes: 5000000
  max_timeout: 30.0
  sampling:
    ratio: 0.05
    strategy: stratified
reports_dir: reports
reporters:
  - terminal
  - json
  - html

reports:
  checkpoint: true
  checkpoint_every: 200
  checkpoint_interval: 30.0

thresholds:
  high: 80
  low: 60
```

Henitai warns on unknown config keys and aborts with `Henitai::ConfigurationError`
when a value is invalid.

CLI flags override the corresponding values from `.henitai.yml`.

`test_excludes` removes matching test files from per-mutant selection. A mutant
with no tests left is reported as `NoCoverage` and is not executed.
`mutation.max_log_bytes` is a positive per-stream byte cap for captured child
output. `mutation.max_timeout` caps auto-calibrated timeouts; an explicit
`mutation.timeout` still takes precedence. When JSON or HTML reporting is
enabled, `reports.checkpoint*` controls periodic canonical-report checkpoints.
Each checkpoint updates `mutation-report.json`; when the HTML reporter is
configured, it also regenerates `mutation-report.html` from that merged JSON.

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

Every forked test child sees a `HENITAI_WORKER_SLOT` environment variable
holding a stable worker-slot index (`0..jobs-1`; always `0` on the linear
path). A flaky-retry respawn keeps the original attempt's value. Test suites
that touch shared external resources can isolate themselves per slot without
any henitai-side hooks — for example a per-worker database:

```ruby
database: "myapp_test_#{ENV.fetch('HENITAI_WORKER_SLOT', '0')}"
```

By default, Henitai keeps child test output out of the live terminal. Each
baseline or mutant run writes captured stdout/stderr to `reports/mutation-logs/`
and the terminal only shows progress plus a concise summary. Pass
`--all-logs` (or `--verbose`) to print every captured child log.

`henitai version` prints the installed version. `henitai run` exits with `0`
when the mutation score meets the low threshold, `1` when it does not, and `2`
for framework errors. With `--strict-exit-codes` (opt-in, additive) it also
exits `3` when one or more mutants timed out and `4` when runtime/compile
errors are present; precedence `2` > `3` > `4` > `1` > `0`. The timeout code
is informational — a run can pass its threshold and still exit `3`.

For pull-request feedback, add the `github` reporter to `reporters:` in
`.henitai.yml`: it prints one `::warning file=...,line=...` workflow command
per survived mutant, so survivors appear as inline annotations on the PR diff
in GitHub Actions. All other statuses stay silent.

`henitai run --incremental` reuses still-valid `Killed` and `Survived`
verdicts from the history store (`reports/mutation-history.sqlite3`) instead
of re-executing them. A `Killed` verdict is reused when the subject's source
and every covering test file are byte-identical to what was recorded. A
`Survived` verdict needs more proof, because a *new* test could now kill it:
it is reused only when, additionally, the live covering set derived from the
current per-test coverage map matches the recorded set exactly (no test
added, dropped, or changed) and the dependency fingerprint (spec helpers,
`spec/support`, fixtures/factories, `Gemfile.lock`, `.henitai.yml`, `.rspec`)
is unchanged. When per-test coverage is unavailable, survivors simply
re-execute — reuse never happens on doubt (see ADR-11).
Reused mutants stay visible in the report (`fromCache: true` beside
`stableId`) and count toward MS/MSI; the terminal prints
`N of M verdicts reused from history (K killed, S survived)` plus an
executed-only MS/MSI line so cached verdicts are never mistaken for fresh
results.
Generated mutants temporarily include `legacyStableId` so scoped runs replace
canonical entries written before site-offset IDs were introduced instead of
duplicating them.
Timeouts and errors always re-execute. `--force` bypasses reuse.
`henitai run --dry-run` lists the post-filter mutant set without executing
mutants and always exits `0`. Gate 0 may still run the configured test suite to
refresh baseline coverage.

Every `henitai run`, including a dry run, acquires a fail-fast advisory lock at
`<reports_dir>/.henitai-run.lock`. `henitai clean` uses the same lock, so it
cannot delete artifacts from a live run. Contention is a framework error (exit
code `2`); direct `Runner#run` callers receive `Henitai::ConcurrentRunError`.
The persistent JSON lock file records the last owner's PID and start time. It
is coordination metadata, not evidence of an active run: the kernel lock is
authoritative, and the file may be the only artifact a dry run creates.

`henitai run --survivors-from ...` performs a partial rerun: it reports only
the selected survivors, skips threshold-based exit checks, and does not update
the run trend history. Dirty worktree changes are included, so you can edit
tests locally without committing first; if source files under `includes` are
dirty, Henitai reruns the matched survivors conservatively.

### Skipping mutations inline

A `# henitai:disable` magic comment excludes code from mutation at the call
site, without touching `.henitai.yml`:

```ruby
def risky_calc(x)
  x * 2 # henitai:disable            — skips mutants on this line
end

# henitai:disable                     — skips every mutant in this method
def legacy_shim(x)
  x - 1
end
```

The line form applies to mutants starting on that line. The method form is a
standalone comment in the contiguous comment block directly above a `def`
(a blank line breaks the association). Trailing text is allowed
(`# henitai:disable -- reviewed defensive branch`). Skipped mutants are
reported as `Ignored`, so they stay visible in the report instead of silently
vanishing. Use `mutation.ignore_patterns` for repo-wide policy and
`# henitai:disable` for one-off, reviewed exclusions.

Directives can also target specific operators, carry a reason (serialized as
`statusReason`, visible in the HTML report), and cover regions:

```ruby
x = a + b  # henitai:disable ArithmeticOperator            — only this operator
x = a + b  # henitai:disable ArithmeticOperator: log noise — with a reason

# henitai:disable RegexMutator: timing-sensitive matcher
def parse(line)
  ...
end

# henitai:disable-start ConditionalExpression
...region...
# henitai:disable-end
```

Operator names must exactly match the canonical names from
`henitai operator list`; unknown names, unmatched or nested
`disable-start`/`disable-end` directives abort the run (exit `2`) with the
offending file and line. Regions do not nest.

The repository ships a JSON Schema at [`assets/schema/henitai.schema.json`](/workspaces/henitai/assets/schema/henitai.schema.json) for editor autocompletion.

## Operator sets

**Light** (default) — high-signal, low-noise operators covering the majority of real-world defects:

- `ArithmeticOperator` — `+` ↔ `-`, `*` ↔ `/`
- `EqualityOperator` — `==` ↔ `!=`, `>` ↔ `<`, etc. (relational operators only)
- `LogicalOperator` — `&&` ↔ `||`
- `BooleanLiteral` — `true` ↔ `false`, `!expr`
- `ConditionalExpression` — remove branch bodies
- `StringLiteral` — empty string replacement
- `ReturnValue` — mutate return expressions

**Full** — adds lower-signal operators:

- `ArrayDeclaration`, `HashLiteral`, `RangeLiteral`
- `MethodChainUnwrap` — remove a link from a method chain
- `RegexMutator` — mutate regexp quantifiers, anchors, char-class negation
- `SafeNavigation` — `&.` → `.`
- `PatternMatch` — case/in arm removal
- `BlockStatement` — remove blocks
- `MethodExpression` — remove calls
- `AssignmentExpression` — mutate compound assignment
- `UnaryOperator` — remove unary `-` and `~`
- `UpdateOperator` — swap compound assignments (`+=`↔`-=`, `*=`↔`/=`, `||=`↔`&&=`)

**Hard** — adds usually-unkillable mutations on top of full, for hunting the
last survivors (see [ADR-12](docs/architecture/adr/ADR-12-hard-operator-set.md)):

- `EqualityIdentityOperator` — `==` ↔ `eql?`/`equal?` (hardest equality pairing to kill; see [ADR-10](docs/architecture/adr/ADR-10-split-equality-identity-mutations.md))
- `HashKeyType` — `{ a: 1 }` → `{ "a" => 1 }` (frameworks that normalize key
  types, e.g. ActiveRecord `order`/`where`, make these mutants equivalent at
  many call sites; disable per site with `# henitai:disable HashKeyType`)

`HashLiteral` (full set) empties the hash and removes one pair at a time
(`{ a: 1, b: 2 }` → `{}` / `{ b: 2 }`).

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

Set `STRYKER_DASHBOARD_API_KEY` in your CI environment to publish reports. When
the key, project, and version are present, the `dashboard` reporter uploads the
Stryker-schema report to the dashboard REST API (default
`https://dashboard.stryker-mutator.io`); otherwise it is skipped silently. The
project defaults to the git remote and the version to the current branch or CI
ref (`GITHUB_REF_NAME`/`GITHUB_REF`/`GITHUB_SHA`).

JSON reports are written to `reports/mutation-report.json` by default. Set
`reports_dir` to change the output directory.

## Development

```sh
git clone https://github.com/martinotten/henitai
cd henitai
bundle install
bundle exec rspec        # run tests
bundle exec ruby bin/verify-process-free-specs # verify self-mutation-safe specs
bundle exec rake smoke:integration:all # run rspec/minitest integration smoke projects
bundle exec rubocop      # lint
bundle exec henitai clean # remove stale generated report artifacts
bundle exec henitai run  # dogfood
```

Framework integration smoke projects live under `spec/fixtures/integration_smoke/`
and exercise `henitai` against small RSpec and Minitest apps via the local path
dependency.

Git hook support is tracked in [`.githooks/pre-commit`](/Users/martinotten/projects/mo/henitai/.githooks/pre-commit).
Enable it with `git config core.hooksPath .githooks` so commits run RuboCop,
RSpec, and the integration smoke suite before they are created.

A Dev Container configuration is included (`.devcontainer/`) for VS Code with the official `ruby:4`
image, the Codex CLI, and RTK preinstalled. Codex support is bootstrapped with
`rtk init -g --codex --auto-patch` during container creation.

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
