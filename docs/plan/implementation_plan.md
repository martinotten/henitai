# Henitai — Implementation Plan

> **Version:** 0.1 · **Status:** March 2026
> **Target platform:** Ruby 4.0.2 · **Gem:** `henitai`
> **Basis:** [architecture.md](../architecture/architecture.md), 39 papers (1992–2025), mutant and Stryker ecosystem analysis

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Component Model](#2-component-model)
3. [Data Flow Through the Pipeline](#3-data-flow-through-the-pipeline)
4. [Implementation Phases](#4-implementation-phases)
   - [Phase 1 - Foundation (MVP)](#phase-1---foundation-mvp)
   - [Phase 2 - Production Ready](#phase-2---production-ready)
   - [Phase 3 - Ecosystem & Intelligence](#phase-3---ecosystem--intelligence)
5. [Task Breakdown](#5-task-breakdown)
6. [Technical Decisions (ADRs)](#6-technical-decisions-adrs)
7. [Quality Criteria](#7-quality-criteria)
8. [Risks & Mitigations](#8-risks--mitigations)

---

## 1. Architecture Overview

Henitai is an **AST-based mutation-testing framework** for Ruby 4. The architecture follows four design principles (fully explained in `../architecture/architecture.md`):

- **Actionability before completeness** - No mutant without developer-visible signal
- **Cost is core, not optional** - Phase-gate pipeline as a mandatory pipeline
- **Extensibility through layers** - Plugin points for operators, reporters, and integrations
- **Ecosystem compatibility** - Stryker JSON schema as the native output format

### System Boundary

```text
┌──────────────────────────────────────────────────────────────────┐
│  Developer / CI                                                   │
│                                                                   │
│  $ bundle exec henitai run --since origin/main 'MyClass#method'   │
└──────────────────────────────┬───────────────────────────────────┘
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│  Henitai (this gem)                                               │
│                                                                   │
│  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌───────────────┐    │
│  │   CLI   │→  │  Runner  │→  │ Pipeline │→  │  Reporters    │    │
│  └─────────┘   └──────────┘   └──────────┘   └───────────────┘    │
└──────────────────────────────────────────────────────────────────┘
         │                                              │
         ▼                                              ▼
  Ruby source code                           JSON / HTML / Dashboard
  RSpec tests                                Terminal summary
  .henitai.yml                               Exit code for CI
```

---

## 2. Component Model

### 2.1 Component Overview

```text
lib/henitai/
├── cli.rb                  # Entry point (OptionParser)
├── configuration.rb        # YAML config + defaults
├── subject.rb              # Addressable code region
├── mutant.rb               # Single mutation + status
├── operator.rb             # Base class for operators
├── operators/              # Concrete operator implementations
│   ├── arithmetic_operator.rb
│   ├── equality_operator.rb
│   ├── logical_operator.rb
│   ├── boolean_literal.rb
│   ├── conditional_expression.rb
│   ├── string_literal.rb
│   ├── return_value.rb
│   ├── safe_navigation.rb
│   ├── range_literal.rb
│   ├── hash_literal.rb
│   ├── pattern_match.rb
│   ├── array_declaration.rb
│   ├── block_statement.rb
│   ├── method_expression.rb
│   └── assignment_expression.rb
├── runner.rb               # Pipeline orchestrator
├── pipeline/               # Phase-gate implementations
│   ├── subject_resolver.rb     # Gate 1
│   ├── mutant_generator.rb     # Gate 2
│   ├── static_filter.rb        # Gate 3
│   ├── execution_engine.rb     # Gate 4
│   └── result_collector.rb     # Gate 5
├── integration/            # Test-framework adapters
│   ├── base.rb
│   └── rspec.rb
├── reporter/               # Output backends
│   ├── base.rb
│   ├── terminal.rb
│   ├── json.rb
│   ├── html.rb
│   └── dashboard.rb
├── result.rb               # Aggregate + Stryker serialization
└── version.rb
```

### 2.2 Dependency Graph

```text
CLI
 └─→ Configuration
 └─→ Runner
       └─→ Pipeline::SubjectResolver  (uses: parser, git)
       └─→ Pipeline::MutantGenerator  (uses: operators, arid filter)
       └─→ Pipeline::StaticFilter      (uses: configuration, coverage)
       └─→ Pipeline::ExecutionEngine   (uses: integration, Process.fork)
       └─→ Pipeline::ResultCollector   (uses: result, reporters)
```

All pipeline components are **stateless** - they receive input, produce output, and keep no global state. The runner holds pipeline state between gates.

### 2.3 Key Data Structures

#### `Subject`
Represents an addressable unit before mutation.

```ruby
Subject = Data.define(
  :namespace,      # "Foo::Bar"
  :method_name,    # "my_method" | nil (wildcard)
  :method_type,    # :instance | :class
  :source_file,    # "/path/to/foo/bar.rb"
  :source_range,   # 42..68 (lines)
  :ast_node        # Parser::AST::Node
)
```

#### `Mutant`
Represents a concrete mutation and its execution status.

```ruby
Mutant = Data.define(
  :id,             # UUID
  :subject,        # Subject
  :operator,       # "ArithmeticOperator"
  :original_node,  # Parser::AST::Node (original)
  :mutated_node,   # Parser::AST::Node (mutated)
  :description,    # "replaced + with -"
  :location,       # { file:, start_line:, end_line:, start_col:, end_col: }
  :status,         # :pending | :killed | :survived | :timeout | ...
  :killing_test,   # String | nil
  :duration        # Float | nil (ms)
)
```

#### `PipelineContext`
Carries the full pipeline state through all gates.

```ruby
PipelineContext = Data.define(
  :config,         # Configuration
  :subjects,       # Array<Subject>
  :mutants,        # Array<Mutant>
  :coverage_map,   # Hash<String, Array<String>>  # file → test_files
  :started_at,     # Time
  :git_diff_files  # Array<String> | nil
)
```

---

## 3. Data Flow Through the Pipeline

```text
.henitai.yml ─→ Configuration
git diff output ─→ GitDiffAnalyzer
                         │
                         ▼
             ┌───────────────────────┐
             │  Gate 1               │
             │  SubjectResolver      │
             │                       │
             │  1. Parse source files│
             │     (Prism)           │
             │  2. Filter by --since │
             │     (git diff)        │
             │  3. Match patterns    │
             │     (CLI args)        │
             └──────────┬────────────┘
                        │  Array<Subject>
                        ▼
             ┌───────────────────────┐
             │  Gate 2               │
             │  MutantGenerator      │
             │                       │
             │  1. AST traversal per │
             │     subject           │
             │  2. Apply operators   │
             │     (light | full)    │
             │  3. Filter arid nodes │
             │  4. Filter stillborn  │
             │     (syntax check)    │
             └──────────┬────────────┘
                        │  Array<Mutant> (status: :pending)
                        ▼
             ┌───────────────────────┐
             │  Gate 3               │
             │  StaticFilter         │
             │                       │
             │  1. ignore_patterns   │
             │     (config regex)    │
             │  2. Coverage data     │
             │     (SimpleCov JSON)  │
             │  3. Mark :no_coverage │
             │     + :ignored        │
             └──────────┬────────────┘
                        │  Array<Mutant> (pending/no_coverage/ignored)
                        ▼
             ┌───────────────────────┐
             │  Gate 4               │
             │  ExecutionEngine      │
             │                       │
             │  Per mutant:          │
             │  1. Fork child        │
             │  2. Inject mutation   │
             │     (define_method)   │
             │  3. Run selected      │
             │     tests (rspec)     │
             │  4. Collect result    │
             │  5. Kill on first     │
             │     failure           │
             └──────────┬────────────┘
                        │  Array<Mutant> (all final)
                        ▼
             ┌───────────────────────┐
             │  Gate 5               │
             │  ResultCollector      │
             │                       │
             │  1. Build Result      │
             │  2. to_stryker_schema │
             │  3. Run reporters     │
             │  4. Exit code         │
             └───────────────────────┘
```

### Mutant Injection (Gate 4 Detail)

The critical implementation detail: mutations are **not** written as temporary files, and RSpec is **not** started as a separate subprocess (`exec` / `system`). Everything runs in the same forked child process:

```ruby
# In the parent process (ExecutionEngine), before fork:
pid = Process.fork do
  # ── CHILD ────────────────────────────────────────────────────────────
  # Step 1: Activate the mutation (before RSpec)
  Activator.activate!(mutant)          # define_method patches target class

  # Step 2: Start tests in the SAME process (no exec!)
  status = RSpec::Core::Runner.run(test_files)
  exit(status ? 0 : 1)
  # ─────────────────────────────────────────────────────────────────────
end

# In the parent process: wait for child and enforce timeout
result = wait_with_timeout(pid, config.timeout)
```

`define_method` patches are process-local - a separate RSpec subprocess would not inherit the patch state. The parent process evaluates the exit code: 0 -> survived, != 0 -> killed, SIGTERM/SIGKILL -> timeout. The `mutant` record is inherited through the fork; no tmpfile is required.

---

## 4. Implementation Phases

### Phase 1 - Foundation (MVP)

**Goal:** A working framework that end-to-end works for a simple Ruby project.

**Definition of Done:**
- `bundle exec henitai run` terminates successfully
- All 7 light-set operators are implemented
- JSON report (Stryker schema) is generated correctly
- CI pipeline (GitHub Actions) is green
- The framework dogfoods itself

**Estimated effort:** 8-12 weeks (single developer, part-time)

---

### Phase 2 - Production Ready

**Goal:** The framework is practical for medium Ruby projects (5,000-20,000 LOC).

**Definition of Done:**
- All light + full operators are implemented
- Incremental mode (`--since`) works reliably
- HTML report via `mutation-testing-elements`
- Stryker Dashboard integration
- Performance: < 10 min for a 10,000 LOC project (with `--since`)

**Estimated effort:** 8-16 weeks after Phase 1

---

### Phase 3 - Ecosystem & Intelligence

**Goal:** Adoption, extensibility, and LLM integration.

**Definition of Done:**
- Plugin API for custom operators is documented and stable
- LLM-based equivalence detector as an optional plugin
- Minitest integration
- Latent-mutant tracking

**Estimated effort:** unbounded / iterative

---

## 5. Task Breakdown

### Legend

| Symbol | Meaning |
|--------|-----------|
| `[ ]` | open |
| `[~]` | stub exists, implementation pending |
| `[x]` | completed |
| `[!]` | blocked / risk |
| **(P1)** | Phase 1 |
| **(P2)** | Phase 2 |
| **(P3)** | Phase 3 |

---

### 5.1 Infrastructure & Gem Setup

- [x] **(P1)** Create gem scaffold (`henitai.gemspec`, `Gemfile`, `.ruby-version`)
- [x] **(P1)** Configure dev container (official `ruby:4.0.2-alpine` base image, Codex CLI preinstalled)
- [x] **(P1)** CI pipeline (GitHub Actions: RSpec + RuboCop + incremental MT on PRs)
- [x] **(P1)** RuboCop configuration (`TargetRubyVersion: 4.0`, frozen strings)
- [x] **(P1)** SimpleCov setup with branch coverage
- [x] **(P1)** Create `.henitai.yml` config schema
- [x] **(P1)** `TASK: infra-01` - Prism spike as go/no-go: verify the Prism/unparser toolchain against Ruby 4.0.2 with real syntax fixtures, including `Prism::Translation::ParserCurrent` if it can produce the `Parser::AST::Node` shape used by `mutant` (`Unparser.parse_ast_either`); the result is either "upstream viable" or "fork / maintenance strategy required". Phase 1 must not start without this decision.
- [ ] **(P1)** `TASK: infra-02` - Steep / RBS type annotations: Phase 1 scope is the public API only. Annotate the stable entry points that callers rely on (`Henitai`, `CLI`, `Configuration`, `Runner`, `Subject`, `Mutant`, `Result`, and any deliberately public extension interfaces such as `Operator` and reporter / integration bases). Leave internal pipeline stages, parser adapters, and concrete operator implementations untyped for now.

---

### 5.2 Configuration (`Configuration`)

- [x] **(P1)** `TASK: config-01` - YAML parser implementation: `YAML.safe_load_file` with symbolization, defaults, and merge semantics
- [x] **(P1)** `TASK: config-02` - CLI override: CLI flags override YAML values (last wins)
- [x] **(P1)** `TASK: config-03` - Validation: warn on unknown keys, abort with a clear error for invalid values
- [x] **(P1)** `TASK: config-04` - Spec: 100% coverage for `Configuration` (unit tests without file-system access via tmp YAML)
- [x] **(P2)** `TASK: config-05` - Schema documentation: generate JSON Schema for `.henitai.yml` (for IDE autocompletion)

---

### 5.3 Subject Resolver (Gate 1)

- [x] **(P1)** `TASK: subject-01` - `SubjectResolver#resolve_from_files(paths)`: parse Ruby files with Prism translation, extract all `def` / `def self.` nodes with namespace context
- [x] **(P1)** `TASK: subject-02` - Namespace resolution: correctly handle nested `module` / `class` definitions in the AST
- [x] **(P1)** `TASK: subject-03` - `SubjectResolver#apply_pattern(subjects, pattern)`: filter the subject list by CLI expressions (`Foo#bar`, `Foo*`, etc.)
- [x] **(P1)** `TASK: subject-04` - `GitDiffAnalyzer#changed_files(from:, to:)`: shell wrapper around `git diff --name-only`, returns `Array<String>`
- [x] **(P1)** `TASK: subject-05` - `GitDiffAnalyzer#changed_methods(from:, to:)`: maps diff hunk line numbers to subject ranges
- [x] **(P1)** `TASK: subject-06` - Spec: edge cases - anonymous classes, singleton classes (`class << self`), `attr_accessor`-generated methods, endless methods (`def f = expr`)
- [ ] **(P2)** `TASK: subject-07` - Metaprogramming detection: capture `define_method` calls as subjects (document the limitation if it cannot be solved)

---

### 5.4 Operator Base Class & Registry

- [x] **(P1)** `TASK: op-01` - `Operator` base class: implement `#mutate(node, subject:)`, `self.node_types`, `#build_mutant`, `#node_location`
- [x] **(P1)** `TASK: op-02` - `Operators` namespace and autoload entries in `henitai.rb`
- [x] **(P1)** `TASK: op-03` - `Operator.for_set(:light)` / `Operator.for_set(:full)`: return instantiated operator objects
- [x] **(P1)** `TASK: op-04` - Arid-node filter: `AridNodeFilter#suppressed?(node, config)` - check against `ignore_patterns` regex list and the built-in catalog (logger, memoization, etc.)
- [x] **(P1)** `TASK: op-05` - Stillborn filter: after mutation run `unparser`, then `RubyVM::InstructionSequence.compile` - discard mutant on `SyntaxError`

---

### 5.5 Concrete Operators (Light Set - Phase 1)

Each operator needs: implementation + spec + at least 3 documented example mutations.

#### ArithmeticOperator
- [x] **(P1)** `TASK: op-arith-01` - Node types: `:send` with methods `+`, `-`, `*`, `/`, `**`, `%`
- [x] **(P1)** `TASK: op-arith-02` - Mutation matrix: `+→-`, `-→+`, `*→/`, `/→*`, `**→*`, `%→*` (symmetrical, no double-counting)
- [x] **(P1)** `TASK: op-arith-03` - Spec: arithmetic with constants, method calls, parentheses, and float literals

#### EqualityOperator
- [x] **(P1)** `TASK: op-eq-01` - Node types: `:send` with `==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`, `eql?`, `equal?`
- [x] **(P1)** `TASK: op-eq-02` - Mutation matrix: replace each operator with every other operator (full 8×8 matrix)
- [x] **(P1)** `TASK: op-eq-03` - Spec: comparisons in conditionals, guard clauses, and `Comparable` implementations

#### LogicalOperator
- [x] **(P1)** `TASK: op-log-01` - Node types: `:and`, `:or`, `&&` / `||` as `:send`
- [x] **(P1)** `TASK: op-log-02` - Mutations: `&&→||`, `||→&&`, `&&→lhs`, `&&→rhs`, `||→lhs`, `||→rhs`
- [x] **(P1)** `TASK: op-log-03` - Spec: preserve short-circuit semantics, `and` / `or` vs `&&` / `||` AST differences

#### BooleanLiteral
- [x] **(P1)** `TASK: op-bool-01` - Node types: `:true`, `:false`, `:send` (`!expr`)
- [x] **(P1)** `TASK: op-bool-02` - Mutations: `true→false`, `false→true`, `!expr→expr`
- [x] **(P1)** `TASK: op-bool-03` - Spec: boolean literals in hash values, default arguments, and ternaries

#### ConditionalExpression
- [x] **(P1)** `TASK: op-cond-01` - Node types: `:if` (including `unless`), `:case`, `:while`, `:until`
- [x] **(P1)** `TASK: op-cond-02` - Mutations: remove then-branch, remove else-branch, negate condition, replace condition with `true` / `false`
- [x] **(P1)** `TASK: op-cond-03` - Spec: modifier-if (`x if cond`), ternary (`cond ? a : b`), `unless`

#### StringLiteral
- [x] **(P1)** `TASK: op-str-01` - Node types: `:str`, `:dstr` (interpolation)
- [x] **(P1)** `TASK: op-str-02` - Mutations: `"foo"→""`, `"foo"→"Henitai was here"`, remove interpolation expression
- [x] **(P1)** `TASK: op-str-03` - Spec: frozen string literals, heredocs, `%w[]` arrays

#### ReturnValue
- [x] **(P1)** `TASK: op-ret-01` - Node types: `:return`, final expression in method body (implicit return)
- [x] **(P1)** `TASK: op-ret-02` - Mutations: `return x` → `return nil`, `return x` → `return 0`, `return x` → `return false`, `return true` / `return false` reciprocally
- [x] **(P1)** `TASK: op-ret-03` - Spec: explicit `return`, implicit final expression, guard-clause `return nil if ...`

---

### 5.6 Concrete Operators (Full Set - Phase 2)

- [x] **(P2)** `TASK: op-safe-01` - `SafeNavigation`: `&.` → `.` (remove nil guard)
- [x] **(P2)** `TASK: op-range-01` - `RangeLiteral`: `..` ↔ `...` (inclusive ↔ exclusive)
- [x] **(P2)** `TASK: op-hash-01` - `HashLiteral`: empty hash replacement, symbol-key mutation
- [x] **(P2)** `TASK: op-pattern-01` - `PatternMatch`: remove `in` arm, mutate guard clause
- [x] **(P2)** `TASK: op-array-01` - `ArrayDeclaration`: `[]` → `[nil]`, remove elements
- [x] **(P2)** `TASK: op-block-01` - `BlockStatement`: `{ ... }` → `{}` (empty block)
- [x] **(P2)** `TASK: op-method-01` - `MethodExpression`: replace method call result with `nil`
- [x] **(P2)** `TASK: op-assign-01` - `AssignmentExpression`: `+=` ↔ `-=`, remove `||=`; documentation and specs must explicitly note that the default arid filter suppresses memoization patterns such as `@var ||= compute_value`

---

### 5.7 Mutant Generator (Gate 2)

- [x] **(P1)** `TASK: gen-01` - `MutantGenerator#generate(subjects, operators)`: AST traversal per subject, applies all active operators to every matching node
- [x] **(P1)** `TASK: gen-02` - AST traversal strategy: `Parser::AST::Processor` subclasses (depth-first, pre-order), operate only within the subject line range
- [x] **(P1)** `TASK: gen-03` - Arid-node integration: check whether the node is suppressed before applying an operator
- [x] **(P1)** `TASK: gen-04` - Stillborn filter integration: after generation call `SyntaxValidator#valid?(mutant)`, discard invalid mutants
- [x] **(P1)** `TASK: gen-05` - `max_mutants_per_line: 1` constraint (Google recommendation): when multiple mutants exist on the same line, keep only the one with the highest signal priority
- [x] **(P2)** `TASK: gen-06` - Stratified sampling: `SamplingStrategy#sample(mutants, ratio:, strategy: :stratified)` - sample by method, not globally

---

### 5.8 Static Filter (Gate 3)

- [x] **(P1)** `TASK: filter-01` - `StaticFilter#apply(mutants, config)`: mark mutants as `:ignored` when the location matches `ignore_patterns`
- [x] **(P1)** `TASK: filter-02` - Coverage integration: read the `SimpleCov` JSON coverage report (`coverage/.resultset.json`), build a `file → [line_numbers]` map
- [x] **(P1)** `TASK: filter-03` - No-coverage marking: mutants whose `start_line` is not in the coverage map receive status `:no_coverage`
- [x] **(P2)** `TASK: filter-04` - Per-test coverage: `SimpleCov::RSpec` integration for a granular `test_file → covered_lines` map (40-60% speedup according to research)

---

### 5.9 Execution Engine (Gate 4)

> **Execution contract (important for correctness):** Each mutant runs in a **forked child process**. Inside that child process, the mutation is injected via `define_method` - *before* RSpec loads spec files. Then `RSpec::Core::Runner.run` is called **in the same child process**. No second `exec` or subprocess is started. `define_method` patches are process-local and would be lost in a separate process.
>
> ```ruby
> # In the parent process (Runner), before fork:
> pid = Process.fork do
>   # ── CHILD ───────────────────────────────────────────────────────────
>   # Step 1: Activate the mutation (before RSpec)
>   Activator.activate!(mutant)          # define_method patches the target class
>
>   # Step 2: Run tests in the SAME process (no exec!)
>   status = RSpec::Core::Runner.run(test_files)
>   exit(status ? 0 : 1)
>   # ────────────────────────────────────────────────────────────────────
> end
>
> # In the parent process: wait for child, enforce timeout
> result = wait_with_timeout(pid, config.timeout)
> ```
>
> **Activation order:** `Activator.activate!` must run before RSpec loads the target source file for the first time. Because RSpec loads source files when spec files are required, calling `activate!` before `RSpec::Core::Runner.run` is sufficient - unless the source file was already loaded in the parent process and copied into the fork. In that case, `activate!` patches the already loaded class directly (which is correct, because `define_method` works on existing classes).

- [ ] **(P1)** `TASK: exec-01` - `ExecutionEngine#run(mutants, integration, config)`: main loop over all `:pending` mutants
- [ ] **(P1)** `TASK: exec-02` - Fork isolation: `Process.fork` per mutant, set `HENITAI_MUTANT_ID` env var, `Process.wait` with timeout in the parent process
- [ ] **(P1)** `TASK: exec-03` - Mutant activation in the child (before RSpec): `Activator.activate!(mutant)` patches the target class via `Module#define_method` - **no exec, no second fork**
- [ ] **(P1)** `TASK: exec-04` - Timeout handling: `Process.kill(:SIGTERM, pid)` after `config.timeout` seconds in the parent process, then `SIGKILL` after another 2 seconds
- [ ] **(P1)** `TASK: exec-05` - Kill-on-first-failure: RSpec formatter reports the first test failure -> child process calls `exit(1)` (no `--fail-fast` needed because it is its own process)
- [ ] **(P1)** `TASK: exec-06` - Exit-code evaluation in the parent process: 0 -> survived, != 0 -> killed, SIGTERM/SIGKILL -> timeout
- [ ] **(P1)** `TASK: exec-07` - `Henitai::Mutant::Activator` class: activates the fork-inherited `Mutant` record in the child and patches target class/method via `Module#define_method`
- [ ] **(P2)** `TASK: exec-08` - Parallel execution: worker pool (`Parallel` gem or native `Ractor`), number via `config.jobs` or CPU count
- [ ] **(P2)** `TASK: exec-09` - Test prioritization: `TestPrioritizer#sort(tests, mutant, history)` - adaptive strategy (tests that have already killed other mutants first)
- [ ] **(P2)** `TASK: exec-10` - Flaky-test mitigation: retry 3 times for a survived mutant, warn when > 5% unknown

---

### 5.10 RSpec Integration

- [ ] **(P1)** `TASK: rspec-01` - `Integration::Rspec#select_tests(subject)`: longest-prefix matching - scan `spec/` for RSpec files whose `describe` / `context` strings contain the subject namespace
- [ ] **(P1)** `TASK: rspec-02` - Fallback: if no tests are found by prefix, use all spec files that transitively `require` the source file
- [ ] **(P1)** `TASK: rspec-03` - `Integration::Rspec#run_in_child(test_files)`: call `RSpec::Core::Runner.run(test_files + rspec_opts)` in the **current process** (called after `fork` by the ExecutionEngine child - no separate subprocess via `exec` or `system`)
- [ ] **(P1)** `TASK: rspec-04` - Ensure activation order: `exec-03` (`Activator.activate!`) is called by `exec-02` (fork) **before** `rspec-03` (`RSpec::Core::Runner.run`) starts. A spec test verifies that the `define_method` patch is active when the first test runs.
- [ ] **(P1)** `TASK: rspec-05` - Integration spec: unit tests for prefix matching logic (no real process needed)
- [ ] **(P2)** `TASK: rspec-06` - Per-test coverage: add `--require henitai/coverage_formatter` to RSpec options, produce `coverage/henitai_per_test.json`
- [ ] **(P3)** `TASK: minitest-01` - Minitest integration analogous to the RSpec integration

---

### 5.11 Reporters

#### Terminal Reporter
- [ ] **(P1)** `TASK: rep-term-01` - Live progress during Gate 4: `·` for killed, `S` for survived, `T` for timeout, `I` for ignored
- [ ] **(P1)** `TASK: rep-term-02` - Summary after Gate 5: table with MS %, killed/survived/timeout/no-coverage counts, duration
- [ ] **(P1)** `TASK: rep-term-03` - Survived details: for each survived mutant show file, line, diff (original vs. mutated), and operator name
- [ ] **(P1)** `TASK: rep-term-04` - Threshold check: colored output (green/yellow/red) based on `thresholds.high` / `thresholds.low`

#### JSON Reporter (Stryker Schema)
- [~] **(P1)** `TASK: rep-json-01` - `Result#to_stryker_schema`: complete implementation including `files` section, `mutants` array, and correct status mapping
- [ ] **(P1)** `TASK: rep-json-02` - File output: `mutation-report.json` in a configurable directory (`reports/`)
- [ ] **(P1)** `TASK: rep-json-03` - Schema validation in specs: validate against JSON Schema v3.5.1 (via `json_schemer` gem)

#### HTML Reporter
- [ ] **(P2)** `TASK: rep-html-01` - HTML template: include `mutation-testing-elements` via CDN (`unpkg.com/mutation-testing-elements`)
- [ ] **(P2)** `TASK: rep-html-02` - Self-contained HTML: embed the JSON report inline as a `<mutation-test-report-app>` web-component attribute
- [ ] **(P2)** `TASK: rep-html-03` - Output: `reports/mutation-report.html`

#### Dashboard Reporter
- [ ] **(P2)** `TASK: rep-dash-01` - REST API client: `PUT /api/reports/{project}/{version}` with bearer auth (`STRYKER_DASHBOARD_API_KEY`)
- [ ] **(P2)** `TASK: rep-dash-02` - Derive project URL from config (`dashboard.project`) or auto-detect from the git remote URL
- [ ] **(P2)** `TASK: rep-dash-03` - CI detection: use `GITHUB_REF` / `GITHUB_SHA` for automatic version resolution

---

### 5.12 CLI

- [~] **(P1)** `TASK: cli-01` - `henitai run`: full pipeline execution with OptionParser
- [ ] **(P1)** `TASK: cli-02` - `henitai run --since GIT_REF`: incremental mode, restrict Gate 1 to changed files
- [ ] **(P1)** `TASK: cli-03` - Exit codes: 0 = MS ≥ low threshold, 1 = MS < low threshold, 2 = framework error
- [ ] **(P1)** `TASK: cli-04` - `henitai version`: print `Henitai::VERSION`
- [ ] **(P2)** `TASK: cli-05` - `henitai init`: create `.henitai.yml` with sensible defaults, ask interactively about integrations
- [ ] **(P2)** `TASK: cli-06` - `henitai operator list`: list all available operators with descriptions and example mutations

---

### 5.13 Result & Scoring

> **Scoring formula (binding, from `../architecture/architecture.md` section 8.4):**
>
> ```text
> MS  = (killed + timeout) / (total − ignored − no_coverage − compile_error − equivalent)
> MSI = killed / total
> ```
>
> `MS` and `MSI` **must always be reported together**. A report without the equivalence caveat is an anti-pattern (`../architecture/architecture.md` section 8.4).
>
> `:equivalent` is an internal Henitai status - in the Stryker JSON it is serialized as `"Ignored"` (the Stryker schema has no Equivalent status). The distinction remains in the `Result` object for correct MS calculation.

- [~] **(P1)** `TASK: result-01` - `Result#mutation_score`: correct MS formula - exclude `:ignored`, `:no_coverage`, `:compile_error`, and **`:equivalent`** from numerator and denominator (implemented in `result.rb`)
- [~] **(P1)** `TASK: result-02` - `Result#mutation_score_indicator`: naive MSI formula - `killed / total`, no exclusions (implemented in `result.rb`)
- [ ] **(P1)** `TASK: result-03` - Terminal report shows MS **and** MSI side by side, plus estimated equivalence uncertainty (`~10-15% of live mutants`)
- [ ] **(P1)** `TASK: result-04` - Spec: MS / MSI calculation with fixture mutants of all statuses, including `:equivalent` (regression guard against formula drift)
- [ ] **(P2)** `TASK: result-05` - Equivalence heuristics (MEDIC patterns): `EquivalenceDetector#analyze(mutant)` marks candidates as `:equivalent` - data-flow patterns (Use-Def, Use-Ret, Def-Def, Def-Ret). Detection rate around 50% of actually equivalent mutants.
- [ ] **(P2)** `TASK: result-06` - Persistent mutant history: `MutantHistoryStore` on SQLite stores `mutant_id`, `first_seen_version`, `status_history`, `days_alive` and forms the basis for latent-mutant tracking
- [ ] **(P2)** `TASK: result-07` - Trend tracking: reporter derives `reports/mutation-history.json` from the SQLite history for MS / MSI trends and persistent live mutants

---

### 5.14 Dogfooding & Quality Assurance

- [ ] **(P1)** `TASK: dog-01` - Henitai tests itself: `bundle exec henitai run --operators light` as part of the CI pipeline (after Phase 1 is complete)
- [ ] **(P1)** `TASK: dog-02` - Test coverage: ≥ 90% statement + branch coverage via SimpleCov
- [ ] **(P1)** `TASK: dog-03` - RuboCop: 0 offenses, `TargetRubyVersion: 4.0`
- [ ] **(P2)** `TASK: dog-04` - Mutation score target: ≥ 70% (light set), ≥ 60% (full set including hard-to-kill operators)
- [ ] **(P2)** `TASK: dog-05` - Performance benchmark: `henitai run` on the repository itself in under 3 minutes

---

## 6. Technical Decisions (ADRs)

The decisions now live in individual files under `../architecture/adr/`. That directory is the canonical source.

Current ADRs:

- [ADR-01: Prism translation instead of `RubyVM::AbstractSyntaxTree`](../architecture/adr/ADR-01-parser-gem-vs-rubyvm-ast.md)
- [ADR-02: `Process.fork` instead of threads or Ractors for test isolation](../architecture/adr/ADR-02-process-fork-for-test-isolation.md)
- [ADR-03: Stryker JSON schema as the native output format](../architecture/adr/ADR-03-stryker-json-native-output.md)
- [ADR-04: `define_method` for mutant injection](../architecture/adr/ADR-04-define_method-for-mutant-injection.md)
- [ADR-05: Stryker-compatible operator names](../architecture/adr/ADR-05-stryker-compatible-operator-names.md)

When a decision changes, update the corresponding ADR file first, then reflect the impact here or in `../architecture/architecture.md`.

---

## 7. Quality Criteria

### 7.1 Definition of Done (per task)

A task is complete when:
1. Implementation is finished (no `raise NotImplementedError`)
2. Specs exist and pass (`bundle exec rspec spec/henitai/[component]`)
3. RuboCop: 0 offenses in the new / changed file
4. SimpleCov: new lines are at least 90% covered
5. `CHANGELOG.md` is updated (under `[Unreleased]`)

### 7.2 Minimum Operator Specification

Each operator must document:
- Which AST node types it handles
- The full mutation matrix (what is replaced with what)
- At least 3 examples with original and mutated code
- Known false-positive sources (arid-node candidates)

### 7.3 Performance Benchmarks (Gate 4 reference)

| Project size | Target (--since, light set) | Target (full run) |
|---|---|---|
| Henitai itself (~500 LOC) | < 30 sec | < 3 min |
| 5,000 LOC | < 3 min | < 20 min |
| 20,000 LOC | < 10 min | < 60 min |

---

## 8. Risks & Mitigations

| # | Risk | Probability | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Prism translation does not fully support Ruby 4.0 syntax | Medium | High | Verify early (TASK: infra-01); fallback: pin or patch Prism translation compatibility |
| R2 | `define_method` injection fails for some methods (e.g. `initialize`, native methods) | High | Medium | Whitelist non-mutable methods; raise explicit errors instead of failing silently |
| R3 | Equivalent mutants erode user trust | Medium | High | Build the arid-node catalog early; add a feedback loop in the CLI |
| R4 | Fork model is not portable to Windows / JRuby | Medium | Low | Document clearly; Windows is a non-goal for Phase 1 |
| R5 | Stryker schema breaking change | Low | Medium | Pin schema version in output; provide a migration guide if needed |
| R6 | RSpec internal APIs for per-test coverage are unstable | Medium | Low | Per-test coverage is P2, not P1; fallback to SimpleCov overall coverage |
| R7 | Ruby 4.0.2 is not stable enough for production | Low | High | Develop against RC / stable; adjust `.ruby-version` if necessary |

---

## Appendix: Recommended Initial Implementation Order (Phase 1)

The component dependency graph suggests this order:

```text
1.  config-01 to config-04         (Configuration - no dependencies)
2.  op-01 to op-05                 (Operator base - no dependencies)
3.  op-arith to op-ret (light set) (7 operators - operator base only)
4.  subject-01 to subject-06       (SubjectResolver - Prism)
5.  gen-01 to gen-05               (MutantGenerator - operators + subjects)
6.  filter-01 to filter-03         (StaticFilter - configuration)
7.  rspec-01 to rspec-05           (RSpec integration - integration base)
8.  exec-01 to exec-06             (ExecutionEngine - integration + mutants)
9.  result-01 to result-03         (Result + Stryker schema)
10. rep-term-01 to rep-term-04     (Terminal reporter)
11. rep-json-01 to rep-json-03     (JSON reporter - result)
12. cli-01 to cli-04               (CLI - everything)
13. dog-01 to dog-03               (Dogfooding - everything)
```

> **Critical path:** config -> operators -> generator -> execution -> result -> CLI
> All other components can be developed in parallel.
