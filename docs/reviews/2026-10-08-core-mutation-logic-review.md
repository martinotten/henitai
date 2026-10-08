# Core Mutation-Testing Logic Review

Date: 2026-10-08
Revision reviewed: `8397c43` (release 0.5.3)
Scope: mutant generation, activation, filtering, execution and status
classification, scoring, verdict reuse, incremental mode, report merging.
Out of scope: CLI ergonomics, HTML rendering, dashboard upload details.
Remediation plan: [`docs/plans/2026-10-08-core-correctness-remediation-plan.md`](../plans/2026-10-08-core-correctness-remediation-plan.md)

## Summary

The pipeline architecture is sound: small operators, explicit gates, stable
mutant identity, content-fingerprint reuse (ADR-11), process isolation, and
ratchet specs. The core weakness is systematic: **many harness defects surface
as `Killed`**. For a mutation-testing tool this is the most harmful failure
mode, because an inflated score hides exactly the test gaps the tool exists to
reveal, and nobody notices. A smaller group of defects produces false
`Survived` verdicts, silently drops mutants, or wastes runtime.

Every finding violates one of four invariants. The remediation plan is
organised around them:

| Invariant | Statement |
|---|---|
| **I1 Fidelity** | The executed code differs from the original by exactly the reported mutation and nothing else. |
| **I2 Honest classification** | `Killed` means a test failed because of the mutation. Harness failures never count as detection. |
| **I3 Sound reuse** | A cached verdict is reused only if every input that produced it is unchanged by content. |
| **I4 Provable equivalence** | A mutant leaves the denominator as `Equivalent` only when equivalence holds without type knowledge. |

Score-effect legend used below:

- **false kill**: the score is inflated
- **false survive**: the score is deflated and the report sends the user chasing a non-gap
- **lost mutant**: the mutant is silently absent from the report
- **wasted**: a run with no information, or a misreported status outside the score
- **perf**: runtime only

## Evidence Levels

| Level | Meaning |
|---|---|
| **R1** | Reproduced end to end, or with an in-process script against the library, during the final verification of this review. |
| **R2** | Reproduced by an area review with a scratch script or throwaway project; not independently re-run. |
| **T** | Precise code trace; no executable reproduction. |

The scratch scripts were not committed. Where a reproduction matters for
remediation, its minimal input is quoted inline so it can become a failing
spec.

## Findings Overview

| ID | Severity | Inv. | Effect | Evidence | Title |
|---|---|---|---|---|---|
| ACT-01 | High | I1 | false kill | R1 | Lexical scope lost on activation; Henitai namespace leaks in |
| ACT-02 | High | I1 | false kill | R1 | `super`, `yield`, `block_given?` broken under `define_method` |
| ACT-03 | Medium | I1 | false kill / wasted | R2 | Parameter reconstruction gaps |
| ACT-04 | Medium | I1 | wasted / false kill | R2 | Heredoc handling truncates or corrupts the method body |
| ACT-05 | High | I1 | wasted / wrong mutant | R1 | Character offsets applied as byte offsets |
| ACT-06 | Low | I1 | wrong mutant | R2 | Splicing ignores operator precedence |
| ACT-07 | Low | I1 | false kill | R2 | Visibility, `__FILE__`/`__LINE__`, `frozen_string_literal` not preserved |
| ACT-08 | Medium | I1 | false survive | R2 | Mutants outside the method body activate the original code |
| EXE-01 | High | I2 | false kill | R1 | Activation and load errors classified as `Killed` |
| EXE-02 | High | I2 | false kill | T | Signal-terminated children classified as `Killed`; `RuntimeError` never produced |
| EXE-03 | High | I2 | false kill | R2 | Timeout calibration ignores boot time |
| EXE-04 | Medium | I2 | false survive | R2 | `SystemExit` raised by code under test classified as `Survived` |
| EXE-05 | Medium | I2 | false kill | R2 | Grandchild holding the output pipe turns a pass into `Timeout` |
| EXE-06 | Low | I2 | wasted | R2 | Zero-example detection is a substring match |
| EXE-07 | Medium | I2 | false kill / perf | T | Flaky-retry policy is inverted |
| EXE-08 | Low | I2 | perf | R2 | Children inherit parent signal traps and wakeup pipe |
| EXE-09 | Low | — | perf | R2 | Ctrl-C does not wake the parallel event loop |
| EXE-10 | Low | — | perf | T | Parallel mode skips process-group cleanup after a normal exit |
| EXE-11 | Medium | — | perf | R2 | Per-test coverage narrowing never applies to RSpec |
| EXE-12 | Medium | I2 | false survive | T | Test selection is name-based first |
| EXE-13 | Medium | I2 | perf / false kill | T | Each child boots the environment; activation happens before load |
| GEN-01 | High | I1 | false kill | R1 | Legacy AST format makes unparse change semantics |
| GEN-02 | High | I1 | false kill | R1 | "Negated condition" emitted without parentheses |
| GEN-03 | High | I1 | wrong mutant | R2 | `elsif` mutants splice a full `if … end` |
| GEN-04 | Medium | I3 | lost mutant | R2 | Stable mutant IDs collide |
| GEN-05 | Medium | — | lost mutant | R2 | Subject patterns reject operator and predicate method names |
| GEN-06 | Medium | I1 | wrong mutant | R2 | ReturnValue matches the final expression structurally |
| GEN-07 | Medium | I1 | wasted | R2 | StringLiteral mutates raw-text children of regexps, `%w`, dsyms |
| GEN-08 | Medium | — | abort | R1 | Source reading depends on the process locale |
| GEN-09 | Low | I1 | wrong mutant | R2 | RegexMutator drops dynamic parts; mislabels negated classes |
| GEN-10 | Low | — | lost mutant | R2 | Subject namespace attribution errors |
| GEN-11 | Low | — | inflated count | R2 | Duplicate mutants across operators |
| FLT-01 | Medium | I4 | false kill (via denominator) | R2 / T | Equivalence detector false positives |
| FLT-02 | Medium | I1 | lost mutant | R2 | Stillborn filter validates fragments without context |
| FLT-03 | Medium | — | lost mutant | R2 | `ignore_patterns` drops enclosing-node mutants instead of reporting `Ignored` |
| FLT-04 | Low | — | bias | T | "Stratified" sampling takes the first N mutants |
| REU-01 | High | I3 | false survive | R2 | `--survivors-from` ignores new or edited tests and caches the result |
| REU-02 | High | I3 | false survive | R2 | `--since --incremental` checks reuse against the previous per-test map |
| REU-03 | High | — | lost mutant | T | Git paths mix repo-root-relative and cwd-relative forms |
| REU-04 | Medium | I3 | false kill | T | Killed-verdict reuse ignores dependency fingerprint and config |
| REU-05 | Medium | — | inflated count | R2 | Canonical merge keeps stale mutants after ID changes |
| REU-06 | Medium | I3 | lost mutant | R2 | Merged report carries the last scoped run's `sessionId`/`gitSha` |
| REU-07 | Low | I3 | wrong history | R2 | History store ignores precomputed `stable_id` of recipe stubs |
| REU-08 | Low | — | trend noise | T | Trend history includes scoped runs |
| REU-09 | Low | — | lost report | R2 | A broken history DB discards the whole run's report |
| REU-10 | Low | — | perf | T | Two-dot diff and partial dashboard upload |
| DOC-01 | Low | — | — | T | Documentation drift (AGENTS.md, ADR-04) |

## Activation (`lib/henitai/mutant/`)

### ACT-01 Lexical scope lost on activation; Henitai namespace leaks in

- **Location:** `lib/henitai/mutant/activator.rb:47` (`target.class_eval(source, __FILE__, …)`), `:76-84` (`define_method` template)
- **Defect:** String `class_eval` builds the constant-lookup scope (cref) from the target plus the caller's lexical chain. Inside the mutated body, `Module.nesting` is `[Outer::Inner, Henitai::Mutant::Activator, Henitai::Mutant, Henitai]` instead of `[Outer::Inner, Outer]`.
- **Reproduction:**
  - **Nested constant:** in `module Outer; LIMIT = 10; class Inner; def m(x) = x > 1 ? LIMIT : 0`, any mutant raises `NameError: uninitialized constant Outer::Inner::LIMIT`.
  - **Class method:** in `class Cfg; DEFAULT = 7; def self.m(x) = x > 1 ? DEFAULT : 0`, the mutant raises `NameError: uninitialized constant #<Class:Cfg>::DEFAULT`.
  - **Class variable:** a class method that reads `@@count` raises `NameError … in Henitai::Mutant::Activator`.
  - **Shadowing:** if the user defines `Result = Struct.new(:v)` at top level, `Result` inside the mutant resolves to `Henitai::Result` and raises `ArgumentError`.
- **Effect:** every mutant in such methods is a false kill. Dogfooding hides this, because Henitai's own constants resolve through the leaked scope.

### ACT-02 `super`, `yield`, `block_given?` broken under `define_method`

- **Location:** `activator.rb:78-80`
- **Defect:** the mutated body runs as a block, not as a method body.
- **Reproduction:**
  - Implicit `super` raises `RuntimeError: implicit argument passing of super from method defined by define_method() is not supported`.
  - `yield 1` raises `LocalJumpError: no block given (yield)`.
  - `block_given?` is always `false`.
- **Effect:** false kills in every method that uses these features. Endless defs such as `def b(x) = yield(x) + 1` fail with `SyntaxError: Invalid yield`, so all their mutants become `CompileError`.

### ACT-03 Parameter reconstruction gaps

- **Location:** `lib/henitai/mutant/parameter_source.rb`, `activator.rb:137-160`
- **Defect:** the parameter list is rebuilt from the AST for a block signature.
  - Argument forwarding (`def m(...) = t(1, ...)`, `def m(*, **, &) = t(*, **, &)`) is not allowed in blocks, so every mutant becomes `CompileError`.
  - Destructuring parameters (`def m((a, b), c)`) lose the `mlhs`, causing an `ArgumentError` and a false kill.
  - `**nil` is silently dropped, which changes the signature.

### ACT-04 Heredoc handling truncates or corrupts the method body

- **Location:** `activator.rb` (`body_source_for_location`)
- **Defect:** the body range ends at the heredoc opener, because the heredoc body lies outside the expression range of the last statement.
  - A heredoc in the final statement (`format(<<~MSG, y)`) truncates the body, so every mutant in the method becomes `CompileError` and leaves the denominator.
  - A StringLiteral mutant on `b = <<~T` becomes `b = ""` and leaves the heredoc body behind as code. That raises `NameError` at runtime, a false kill.

### ACT-05 Character offsets applied as byte offsets

- **Location:** `activator.rb:198-206` (`replace_source_fragment`)
- **Defect:** Parser source ranges count characters, but the splice uses `byteslice` and `bytesize`.
- **Reproduction:** a body containing `label = "größe"` followed by `x + 1 > 2`. The `+` → `-` mutant is spliced as `x - 1 1 > 2`, which is a SyntaxError and becomes `CompileError`. The `>` → `<` mutant becomes `x + 1 < 2 2`.
- **Effect:** any non-ASCII character earlier in a method, including in a comment, corrupts every later mutant. Some shifts compile into a different mutation than the one reported.

### ACT-06 Splicing ignores operator precedence

- **Location:** `activator.rb:206-217`
- **Reproduction:** the `**` → `*` mutant in `a / x ** 2` is spliced as the text `a / x * 2`, which evaluates as `(a / x) * 2`. For `m(100, 5)` the result is 40 instead of the intended 10.
- **Effect:** the executed mutant is not the reported one.

### ACT-07 Visibility, `__FILE__`/`__LINE__`, `frozen_string_literal` not preserved

- **Location:** `activator.rb:76-84`
- **Defects:**
  - Private and protected methods become public.
  - `__FILE__`, `__dir__` and `__LINE__` resolve to `activator.rb`, which breaks `require_relative` and template paths in the mutated body.
  - `# frozen_string_literal: true` is lost: `"abc".frozen?` returns `false`.

### ACT-08 Mutants outside the method body activate the original code

- **Location:** `lib/henitai/mutant_generator.rb:84` (walks every child of the subject node), `activator.rb:106/109` (fallback to the unmutated body)
- **Reproduction:**
  - `def bar(x = 1 + 2, y: "k")` yields `+` → `-` and StringLiteral mutants, but the activation source still contains `|x = 1 + 2, y: "k"|`.
  - `define_method(:baz) do |a| … end` yields BlockStatement and MethodExpression mutants on the `define_method` call; all of them activate the original body.
- **Effect:** guaranteed false survives.

## Execution and Classification

### EXE-01 Activation and load errors classified as `Killed`

- **Location:**
  - `activator.rb:49` rescues only `Unparser::UnsupportedNodeError` and `SyntaxError`.
  - `activator.rb:166-170` (`load_target` → `load_source_file`)
  - `lib/henitai/integration/mutant_run_support.rb:68`
  - `lib/henitai/scenario_execution_result.rb:91-99`
- **Defect:** activation runs before spec files are loaded. The activator therefore `load`s the subject file itself. Any class-body reference to a constant from another file raises `NameError`: a superclass in a sibling file, compact `class A::B`, `extend Forwardable`, `ApplicationRecord`. The exception escapes the fork block, Ruby exits with status 1, and `status_for` maps that to `:killed`.
- **Reproduction:** `lib/shop/cart.rb` contains `class Cart < Base`, with `Base` defined in a sibling file that `lib/shop.rb` requires. The single spec asserts nothing. `henitai run` reports **9/9 Killed and exits 0**.
- **Note:** ADR-04 already requires that "activation failures must be classified separately"; this is not implemented.

### EXE-02 Signal-terminated children classified as `Killed`

- **Location:** `scenario_execution_result.rb:91-99`
- **Defect:** for a signalled process, `Process::Status#success?` is `nil`, so the status falls through to `:killed`. Crashes therefore count as kills: SIGSEGV, SIGKILL (the OOM killer), `abort`. `:runtime_error`, which `coverage_criteria.process_abort` expects, is never produced by this path.

### EXE-03 Timeout calibration ignores boot time

- **Location:** `lib/henitai/timeout_calibrator.rb:31`, `lib/henitai/execution_engine.rb:137`, `lib/henitai/coverage_formatter.rb:19`
- **Defect:** the timeout is `3 × Σ per-example run_time`, with a 2 s floor.
  - Loading `spec_helper` or `rails_helper`, loading the spec files and running `before(:suite)` or `before(:all)` are all excluded from the measurement.
  - The 30 s `max_timeout` cap applies even when the measured baseline exceeds it.
- **Reproduction:** `spec_helper` sleeps 2.5 s and the single example asserts nothing. The result is 4/4 `Timeout`, a score of 100%, and exit 0.

### EXE-04 `SystemExit` raised by code under test classified as `Survived`

- **Location:** `lib/henitai/integration/rspec_child_runner.rb:21-23` (re-raises), `mutant_run_support.rb:71`, `rspec_process_runner.rb:95`. Minitest's `PASSTHROUGH_EXCEPTIONS` behaves the same way.
- **Defect:** the child exits 0 midway through the suite.
- **Reproduction:** `return :ok if done; exit(0)`. The mutants `if false`, `if !done` and `nil` survive, and the log shows "1 example, 0 failures" out of 2.

### EXE-05 Grandchild holding the output pipe turns a pass into `Timeout`

- **Location:** `lib/henitai/integration/scenario_log_support.rb:96-100` (read loop at `:80`)
- **Defect:** `finish_capped_stream` joins the reader thread, which waits for EOF. A process spawned by the tests that inherited fd 1/2 keeps the pipe open until the process group is killed. The baseline writes to files, so it never shows the problem.
- **Reproduction:** an example that runs `Process.detach(spawn("sleep", "20"))` gives 4/4 `Timeout` while the log says "1 example, 0 failures".

### EXE-06 Zero-example detection is a substring match

- **Location:** `scenario_execution_result.rb:113-117`
- **Defect:** `"10 examples, 0 failures, 1 error occurred outside of examples"` contains `"0 examples, 0 failures"`, so the result is classified `:compile_error`. A real kill caused by a load-time or `before(:suite)` failure triggered by the mutant is also removed from the denominator.

### EXE-07 Flaky-retry policy is inverted

- **Location:** `lib/henitai/slot_scheduler/retry_policy.rb:16`
- **Defect:** only `Survived` is retried, on the reasoning that "a kill cannot be faked by flakiness". Ordinary flakiness produces spurious *failures*, though.
  - With a test that fails 10% of the time, an unkillable mutant becomes `Killed` with probability 1 − 0.9⁴ ≈ 34% under the default 3 retries, instead of 10%.
  - Every genuine survivor costs four runs.
  - The ">5% needed a retry" warning fires whenever more than 5% of mutants survive, so it carries no flakiness information.

### EXE-08 Children inherit parent signal traps and wakeup pipe

- **Location:** `lib/henitai/process_worker_runner.rb:139`, `lib/henitai/integration/child_bootstrap.rb`
- **Defect:** a forked child keeps the parent's `@shutdown_requested = true` SIGTERM handler and ignores SIGTERM. The graceful drain phase never works, and child `ensure`/`at_exit` cleanup never runs on timeout.

### EXE-09 Ctrl-C does not wake the parallel event loop

- **Location:** `process_worker_runner.rb:139`
- **Defect:** the trap only sets a flag, and Ruby retries `IO.select` after the handler returns. Shutdown therefore waits for the next child exit or slot deadline. Fix direction: signal the wakeup pipe from the trap.

### EXE-10 Parallel mode skips process-group cleanup after a normal exit

- **Location:** `lib/henitai/slot_scheduler.rb:157` (`complete_slot`)
- **Defect:** the linear path calls `cleanup_process_group`; the scheduler does not, so daemons spawned by tests leak. On the linear path, cleanup runs after reaping and waits the full 2 s grace period whenever a grandchild survives.

### EXE-11 Per-test coverage narrowing never applies to RSpec

- **Location:** `lib/henitai/per_test_coverage.rb:67`
- **Defect:** the map is keyed by RSpec `file_path` (`"./spec/x_spec.rb"`), while candidates come from `Dir.glob` (`"spec/x_spec.rb"`). `covers?` is always false, so selection always falls back to all candidates. This is the largest single avoidable runtime cost found.

### EXE-12 Test selection is name-based first

- **Location:** `lib/henitai/per_test_coverage_selector.rb`, `lib/henitai/test_prioritizer.rb`
- **Defect:** per-test coverage can only narrow the name-matched candidates, never add to them. Tests that provably execute the mutated line but do not mention the constant are never run. A weak `tax_spec` that mentions `Shop::Tax` hides a strong `cart_spec`, producing a false survive.

### EXE-13 Each child boots the environment; activation happens before load

- **Location:** `mutant_run_support.rb:63-74`, `rspec_child_runner.rb:44-50`
- **Defect:** each forked child first activates the mutant, then loads the spec files (and with them `spec_helper`/`rails_helper` and the application), then runs. The boot cost is paid once per mutant. Activating before the environment is loaded is the root cause of EXE-01. Correctness also depends on `$LOADED_FEATURES` bookkeeping (`activator.rb:178-180`) to keep a later `require` from overwriting the mutant. Autoloaders do not go through that path.

## Mutant Generation

### GEN-01 Legacy AST format makes unparse change semantics

- **Location:** `lib/henitai/source_parser.rb:35`
- **Defect:** the Prism translation builder runs with all legacy `emit_*` flags (`emit_procarg0`, `emit_kwargs`, `emit_lambda`, …) disabled. Unparser only round-trips the modern format, so re-unparsed subtrees change meaning:
  - a one-parameter block `|x|` becomes `|x,|`, which destructures arrays
  - keyword arguments become a braced positional hash
- **Reproduction:**
  - `pairs.map { |pr| pr.first }.sum + 1` with `+` → `-` is emitted as `pairs.map { |pr,| pr.first }.sum - 1` and raises `NoMethodError` on `[[1, 2], [3, 4]]`.
  - `build(name: x, size: 2)` against `def build(name:, size:)`: every HashLiteral mutant raises `ArgumentError`.
- **Effect:** a second, unintended change makes tests fail, a false kill. Any operator that re-unparses an enclosing node is affected; the ConditionalExpression mutants re-unparse the whole `if`.

### GEN-02 "Negated condition" emitted without parentheses

- **Location:** `lib/henitai/operators/conditional_expression.rb:157` (`negate` builds `(send cond :!)`)
- **Reproduction:** `if i > 3` becomes `if !i > 3`, which raises `NoMethodError: undefined method '>' for false`.
- **Effect:** this operator is in the default **light** set. Every negated binary condition is a crash mutant and a false kill.

### GEN-03 `elsif` mutants splice a full `if … end`

- **Location:** `conditional_expression.rb:30` together with the activator splice
- **Defect:** an `elsif` node's range starts at `elsif` and has no `end`. Splicing a freshly unparsed `if … end` nests it inside the then-branch.
- **Reproduction:** in `if a; 1; elsif b; 2; else; 3; end`, the "replaced condition with true" mutant on the `elsif` returns `[2, nil, nil]` for (T,F), (F,T), (F,F); the expected result is `[1, 2, 2]`.

### GEN-04 Stable mutant IDs collide

- **Location:** `lib/henitai/mutant_identity.rb:50`
- **Defect:** the identity hashes the subject, operator, description, file, unparsed mutated node and start line/column only.
- **Reproduction:** `x.a.b.c` yields three "replaced method call with nil" mutants with the same ID.
- **Effect:**
  - `SurvivorSelector#select` (`to_h`) drops survivors.
  - `SurvivorActivationCache` overwrites recipes.
  - The history store merges rows.

### GEN-05 Subject patterns reject operator and predicate method names

- **Location:** `lib/henitai/subject.rb:59` (`\w+`)
- **Defect:** `Foo#empty?`, `Foo#save!`, `Foo#name=`, `Foo#==` and `Foo#[]` fall into the wildcard branch and match nothing.

### GEN-06 ReturnValue matches the final expression structurally

- **Location:** `lib/henitai/operators/return_value.rb:50`
- **Defect:** `AST::Node#==` ignores location, so structurally identical earlier nodes also match.
- **Reproduction:**
  - In `return true if x.ok?; notify(x); x.ok?`, the guard condition is mutated as if it were the final expression.
  - In `a.save; a.save`, both lines are mutated.
- **Fix direction:** compare with `equal?`.

### GEN-07 StringLiteral mutates raw-text children

- **Location:** `mutant_generator.rb:89` (the guard covers only `dstr` parents)
- **Defect:** raw-text `str` children of other constructs are mutated as if they were string literals:
  - `/foo/` becomes `/""/`
  - `%w[alpha beta]` becomes `%w["" beta]`
  - `:"k#{y}"` becomes `:"""#{y}"` (SyntaxError)
  - heredoc segments receive literal quote characters

### GEN-08 Source reading depends on the process locale

- **Location:** `source_parser.rb:41` (`File.read` with the default external encoding)
- **Defect:** with `LANG` unset or `C`, any UTF-8 source file raises `EncodingError: invalid byte sequence in US-ASCII`, which aborts subject resolution. Ruby itself reads source files as UTF-8.

### GEN-09 RegexMutator drops dynamic parts and mislabels negated classes

- **Location:** `lib/henitai/operators/regex_mutator.rb:33`, `:70`
- **Defects:**
  - `/ab+#{y}cd/` becomes `/ab*/`; the interpolation and suffix are dropped.
  - `/[^0-9]+/` becomes `/[0-9]+/`, reported as "removed ^ anchor".

### GEN-10 Subject namespace attribution errors

- **Location:** `lib/henitai/subject_resolver.rb:79`, `:88`, `:104`
- **Defects:**
  - `module Outer; class ::TopLevel` resolves to `Outer::TopLevel`.
  - `def Other.e` inside `Outer` resolves to `Outer.e`.
  - `class << obj` is treated as `class << self`.
  - Methods inside `Struct.new(...) do … end` and `Data.define do … end` are never subjects.

### GEN-11 Duplicate mutants across operators

- **Defects:**
  - In `return true if x`, BooleanLiteral and ReturnValue both emit `return false`.
  - On a final `false`, both emit `true`.
  - For an `if` without `else`, "replaced condition with false" and "removed then branch" are identical.

## Filtering and Equivalence

### FLT-01 Equivalence detector false positives

- **Location:** `lib/henitai/equivalence_detector.rb:86-98`, `:54`, `:153-161`; `equivalence_detector/operand_predicates.rb:28`
- **Defects:** rules keyed on a literal operand with an unknown receiver are unsound:
  - **`x || false` → `x` and `x && true` → `x`:** these are flagged equivalent, but `nil || false` is `false`, not `nil`, and `5 && true` is `true`, not `5`. Only the left-literal forms `false || x` and `true && x` are sound.
  - **`"ab" * 1` → `"ab" / 1`:** flagged, but the original returns `"ab"` and the mutant raises. Arrays behave the same way.
  - **`x == "a"` ↔ `x.eql?("a")`:** unsound for receivers with a custom `==`, and for `"a" == obj` when `obj` implements `to_str`.
  - **`x - 0` ↔ `x + 0`:** differs for `-0.0` (low impact).
- **Effect:** these mutants leave both numerator and denominator, which inflates MS.

### FLT-02 Stillborn filter validates fragments without context

- **Location:** `lib/henitai/stillborn_filter.rb:8-31`
- **Defect:** the mutated node is compiled inside a bare parameterless `def`.
  - `next`, `break`, `redo` and `retry` raise "Invalid next", so valid mutants of `next if i > 3` are dropped silently.
  - Anonymous-parameter forwarding (`def a(*) = helper(*) + 1`) drops every mutant of the method.
- **Fix direction:** validate the actual activation source instead.

### FLT-03 `ignore_patterns` drops enclosing-node mutants instead of reporting `Ignored`

- **Location:** `lib/henitai/arid_node_filter.rb:18-24`, `mutant_generator.rb:100`
- **Defect:** the regex is matched against the full source of every node, so an `if` or block containing the pattern loses all of its own mutants. With the pattern `audit_log`, 7 of 16 mutants vanished.
- **Effect:** filtering happens at generation time, so `StaticFilter#ignored?` (`static_filter.rb:66-82`) never sees these mutants. They are dropped instead of being reported as `Ignored`, contrary to `docs/backlog/2026-07-02-inline-mutation-skip-annotations.md`.

### FLT-04 "Stratified" sampling takes the first N mutants

- **Location:** `lib/henitai/sampling_strategy.rb`
- **Defect:** sampling takes the first N mutants per subject in AST-walk order, which biases the sample toward the top of each method and toward the first operator.

## Verdict Reuse, Incremental Mode, Reports

### REU-01 `--survivors-from` ignores new or edited tests and caches the result

- **Location:** `lib/henitai/survivor_test_filter.rb:56-66`, `dirty_source_detector.rb:8-11`, `survivor_rerun_strategy.rb:135-137`
- **Defect:** a survivor is treated as stable, marked `Survived` and never run, unless one of its *previously recorded* `coveredBy` files changed. A new spec file, or an edited `spec/support` helper, is ignored.
  - `finalize_survivor_split` sets `:survived` without `from_cache`.
  - `VerdictCache#survived_cache_bindings` then writes a fresh fingerprint against the live map, so a later `--incremental` run reuses the false survive.
- **Reproduction:** coverage map `{S => [spec/a_spec.rb]}` plus an untracked killing `spec/b_spec.rb` gives `stable: ["S"]` and `dirty?: false`. This breaks the core "add a test, watch the survivor flip" loop.

### REU-02 `--since --incremental` checks reuse against the previous per-test map

- **Location:** `lib/henitai/per_test_coverage.rb:75` (memoized `map`), `source_file_selection.rb:68`, `runner_dependencies.rb:37`, `incremental_filter.rb:85`
- **Defect:** Gate 1 loads and memoizes the old `henitai_per_test.json` before Gate 0 rewrites it. The shared instance is then used for reuse decisions, so a new covering test is not seen.

### REU-03 Git paths mix repo-root-relative and cwd-relative forms

- **Location:** `lib/henitai/git_diff_analyzer.rb:14-19`, `:97-114`
- **Defect:** `git diff --name-only` prints paths relative to the repository root; `git ls-files --others` prints them relative to the cwd. All consumers expand the paths against the cwd. Non-ASCII paths are additionally quoted (`"app/lib/gr\303\266\303\237e.rb"`).
- **Effect:** in a project below the git root:
  - `--since` mutates nothing that was committed and exits 0.
  - `DirtySourceDetector` reports clean.
  - `SurvivorTestFilter` never matches.
- **Fix direction:** `--relative` (or resolve against `rev-parse --show-toplevel`) together with `-z`.

### REU-04 Killed-verdict reuse ignores dependency fingerprint and config

- **Location:** `lib/henitai/incremental_filter.rb:76-79`
- **Defect:** only the subject source and the `covered_by` file contents are checked. The following never invalidate a cached `Killed`, although ADR-11 already lists them in `DEPENDENCY_GLOBS` for `Survived`:
  - edits to `spec/support/**`
  - edits to `spec_helper.rb`
  - a `test_excludes` change that excludes the only killing test

### REU-05 Canonical merge keeps stale mutants after ID changes

- **Location:** `lib/henitai/canonical_report_merger.rb:38-77`
- **Defect:** prior mutants are replaced only when their `stableId` reappears. Inserting a line in a method changes most of its IDs, so old entries linger next to the new ones. Entries of deleted methods linger too.
- **Effect:** duplicated counts and out-of-range locations in the HTML report.

### REU-06 Merged report carries the last scoped run's `sessionId`/`gitSha`

- **Location:** `canonical_report_merger.rb:43`, `lib/henitai/cli/run_command.rb:56-78`
- **Defect:** `--survivors-from reports/mutation-report.json` follows `sessionId` to a snapshot that holds only the last scoped run's mutants, so survivors from other files are skipped. Without that redirect, `gitSha` is younger than other files' entries, and diff-based checks start from the wrong base.

### REU-07 History store ignores precomputed `stable_id` of recipe stubs

- **Location:** `lib/henitai/mutant_history_store.rb:136`
- **Defects:**
  - `MutantIdentity.stable_id(mutant)` recomputes a synthetic ID for stubs without nodes, so distinct stubs collapse into one row.
  - Stubs serialize `replacement: ""` and overwrite the real replacement in the report.

### REU-08 Trend history includes scoped runs

- **Location:** `mutant_history_store.rb:33`
- **Defect:** only `partial_rerun?` is excluded, so `--since` and subject-pattern runs are recorded as full runs, and the trend MS/MSI jumps with scope. ADR-09 intends full runs only.

### REU-09 A broken history DB discards the whole run's report

- **Location:** `lib/henitai/runner.rb:161-164`
- **Defect:** `persist_history` runs before `report`. A corrupt or locked SQLite file raises, the CLI exits 2, and no JSON/HTML report is written after a full execution.

### REU-10 Two-dot diff and partial dashboard upload

- **Defects:**
  - `--since` uses `git diff REF HEAD` instead of `REF...HEAD`, so commits that landed on the base branch are selected as well. This is safe but wasteful.
  - `Reporter::Dashboard` uploads only the current run, so a `--since` run replaces the dashboard version with a partial report.
- A related minor point: mutants left `:pending` by an interrupted run count in both denominators.

## Documentation

### DOC-01 Documentation drift

- `AGENTS.md` describes a "Thread+Queue worker pool". The implementation is a single-threaded `ProcessWorkerRunner` event loop with `SlotScheduler`.
- ADR-04's consequence "activation failures must be classified separately" is not implemented (see EXE-01).
- ADR-04's stated drivers (no disk I/O, no write contention) are equally met by evaluating a `def` string in memory, so the decision does not follow from its own context. See ADR-13.

## Verified Correct

These areas were checked and need no change:

- **Scoring:** the MS and MSI formulas match `AGENTS.md`. `coverage_criteria` toggles affect only the numerator, and an empty denominator yields `nil`.
- **Exit codes:** precedence is 2 > 3 > 4 > 1 > 0. The threshold comparison is safe because thresholds are validated as Integer.
- **Report locations:** 0-based columns are converted to 1-based, with an exclusive end.
- **Status mapping:** `Equivalent` is serialized as `Ignored`.
- **SQL:** queries use bind parameters only; migrations interpolate constants only.

## Cross-Cutting Root Causes

1. **Activation by `define_method` in a string `class_eval`** (ADR-04) causes ACT-01, ACT-02, ACT-03 and ACT-07.
2. **Whole-subtree unparse plus text splice** causes GEN-01, GEN-02, GEN-03, ACT-04, ACT-05, ACT-06 and GEN-07. The missing check that the activated source differs from the original by exactly one node lets all of them reach execution.
3. **No explicit child-to-parent status contract.** A three-way exit-code heuristic (2 → `compile_error`, 0 → `survived`, otherwise `killed`) causes EXE-01, EXE-02, EXE-04 and EXE-06.
4. **Different execution models for the baseline and mutant runs** (a spawned process writing to files, versus a fork that activates before load and writes to a pipe) cause EXE-01, EXE-03, EXE-05 and EXE-13. Such differences surface only as false detections.
5. **Two reuse mechanisms with different soundness rules.** `SurvivorTestFilter` is git-based; `IncrementalFilter` is content-based. This causes REU-01 and REU-06. Snapshot timing of the shared `PerTestCoverage` (REU-02) and the lack of per-file provenance in the canonical report (REU-05, REU-06) add to it.
6. **No measurement of reliability.** There is no oracle corpus with known expected statuses, and no smoke fixture covers nested namespaces, class methods, `super`/`yield`, UTF-8, heredocs, sub-directory projects or a slow boot. Dogfooding hides ACT-01.
