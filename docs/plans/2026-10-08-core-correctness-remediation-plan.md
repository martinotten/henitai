# Core Correctness Remediation Plan

Date: 2026-10-08
Status: proposed
Findings: [`docs/reviews/2026-10-08-core-mutation-logic-review.md`](../reviews/2026-10-08-core-mutation-logic-review.md)
Related decision: [ADR-13](../architecture/adr/ADR-13-def-injection-in-lexical-nesting.md) (proposed, supersedes ADR-04)

## Goal

A mutation-testing framework whose verdicts can be trusted and that runs fast.
Correctness takes priority over speed. Caching, reuse and parallelism built on
unsound verdicts multiply the error. Several correctness fixes also remove
large amounts of wasted runtime.

Success is defined by the four invariants from the review:

| Invariant | Statement | Measured by |
|---|---|---|
| **I1 Fidelity** | The executed code differs from the original by exactly the reported mutation. | The fidelity check (WS0) passes for 100% of the executed mutants in the oracle corpus and the dogfood run. |
| **I2 Honest classification** | `Killed` means a test failed because of the mutation. | The oracle corpus has a false-kill rate of 0. Harness failures appear as `CompileError` or `RuntimeError`, never as `Killed`. |
| **I3 Sound reuse** | A reused verdict has unchanged inputs. | The reuse property specs (WS5) hold. An incremental run's verdicts equal a full run's verdicts on the oracle corpus after scripted edits. |
| **I4 Provable equivalence** | `Equivalent` only when provable without types. | Every equivalence rule has a counter-example spec showing why it is sound. |

Speed goals, measured on the dogfood run and one Rails-shaped fixture against
the 0.5.3 baseline:

- per-mutant wall time does not include the environment boot (WS4)
- per-test narrowing is effective for RSpec (EXE-11)
- no mutant is executed more than once unless a policy explicitly requires it (EXE-07)

## Guiding Principles

1. **Measure first.** Install the safety nets (WS0) before changing behaviour, so every later step shows whether it made verdicts more correct or merely different.
2. **Fail loudly in the harness.** A defect in Henitai must surface as a harness status that stays out of the score and is reported, never as a detection.
3. **One mechanism per concern.** Use one activation path, one reuse mechanism and one child status contract, each with a single soundness argument.
4. **The baseline and mutant runs share an execution model.** Anything that differs between the two shows up only as a false verdict.
5. **TDD and ratchets as usual.** Every finding gets a failing spec first (`CODE_PRINCIPLES.md`). Capture host MS/MSI before an extraction and re-measure afterwards (`AGENTS.md`).

## Workstreams

### WS0: Safety Nets and Measurement

Findings: none directly; this workstream enables measuring all others.

1. **Oracle corpus** under `spec/fixtures/oracle/`.
   - Small Ruby snippets, each with a tiny test suite and a manifest of the expected status per mutant (killable and killed, survivable, equivalent, crash).
   - It must cover the constructs from the review: nested namespaces, class methods, class variables, `super`/`yield`/`block_given?`, forwarding parameters, destructuring, heredocs, UTF-8 before a mutation site, `elsif`, precedence, keyword arguments, one-parameter blocks, `SystemExit`, signals, and a slow boot.
   - A rake task reports the false-kill and false-survive rates.
2. **Smoke fixtures** that add the shapes the current fixtures miss:
   - a project in a sub-directory of its git repository
   - a multi-file namespace with a superclass in a sibling file
   - a slow `spec_helper`
   - a test that spawns a background process
3. **Static fidelity check.**
   - Parse the activation source and the original method, then diff the ASTs. The difference must be exactly `original_node → mutated_node`.
   - Any other difference becomes a harness status (`CompileError` with a reason) before execution and is listed in the report.
   - The check costs milliseconds per mutant.
4. **Dynamic control run (noop mutant).**
   - Per selected test-file set, run the *unmutated* body through the full activation and fork path once. It must pass.
   - If it fails, the subject's mutants are reported as harness errors, not executed. This catches every remaining activation-fidelity defect at run time.
5. **Baseline numbers.** Record dogfood MS/MSI, wall time, the oracle rates and the fixture results for 0.5.3 before WS1 starts.

Acceptance:

- The oracle task runs in CI.
- On 0.5.3, the fidelity check and the control run flag the known R1 findings (ACT-01, ACT-02, ACT-05, GEN-01, GEN-02). This proves the nets catch them.

### WS1: Child-to-Parent Status Contract

Findings: EXE-01, EXE-02, EXE-04, EXE-06, EXE-08, and the ADR-04 consequence from DOC-01.

1. Replace the exit-code heuristic in `ScenarioExecutionResult.status_for` with an explicit contract. The child writes a small status record (a file in its log directory, or reserved exit codes) for each outcome:
   - activation failed (with the exception)
   - environment load failed
   - tests completed (with the example and failure counts)
   - `SystemExit` raised during the tests
2. The parent maps the record to a status:
   - **no record and a signal or abnormal exit:** `RuntimeError` (EXE-02)
   - **activation or load failed:** `CompileError` with the reason in the report (EXE-01)
   - **tests ran with failures > 0:** `Killed`
   - **failures = 0:** `Survived`
   - **examples = 0:** `CompileError` (EXE-06), using the counts from the record instead of matching on stdout
3. The child rescues `StandardError` and `ScriptError` around activation, and `SystemExit` around the test run (EXE-04). The classification of `SystemExit` is decision D2.
4. `ChildBootstrap.after_fork!` resets the INT, TERM and HUP traps to `SYSTEM_DEFAULT` and closes inherited wakeup-pipe file descriptors (EXE-08).

Acceptance:

- The EXE-01 reproduction (`class Cart < Base` in a sibling file, spec without assertions) reports `CompileError`, not `Killed`, and the run exits non-zero against the threshold.
- SIGKILL, SIGSEGV and `abort` produce `RuntimeError`.
- `"10 examples, 0 failures, 1 error occurred outside of examples"` is not classified as zero examples.

### WS2: Activation Fidelity (ADR-13)

Findings: ACT-01 to ACT-08, FLT-02, and EXE-13 (the activation order).

1. **Inject a real `def` into the original lexical nesting.**
   - The nesting is taken from the AST: the subject resolver records the enclosing `module`/`class`/`class << self` nodes, including the compact `class A::B` form.
   - The `def` is evaluated with `TOPLEVEL_BINDING.eval(source, original_file, line)`.
   - The original `def` header is copied verbatim, so `ParameterSource` is no longer needed on this path (ACT-03).
2. **Splice inside the full `def` source range,** not inside the body range.
   - Mutations in default values become activatable (ACT-08).
   - Heredoc bodies are included in the range (ACT-04).
3. **Restore what `def` does not carry over.** Capture the method's visibility and its `module_function` state before injection, and re-apply them afterwards (ACT-07). Keep the magic comments of the source file, including `frozen_string_literal`.
4. **Keep `define_method` as a documented fallback** for subjects that cannot be reopened: `define_method` subjects, methods inside `Struct.new`/`Data.define` blocks, and `class << obj`. The report marks mutants activated this way.
5. **Activate after the environment has loaded.** The order becomes: load the environment and the spec files, then activate, then run. This removes the activator's own `load` of the subject file and the `$LOADED_FEATURES` workaround (EXE-13). It interacts with WS4 (fork server).
6. **Make the stillborn filter validate the real activation source** (FLT-02). It reuses the WS0 fidelity parse.
7. **Bump the recipe format version** in `SurvivorActivationCache` and the precomputed activation sources, so stale recipes are not reused.

Acceptance:

- Every ACT reproduction in the review is a passing spec.
- The oracle corpus has no activation-caused false kill.
- Dogfood MS/MSI is re-measured. Expect a drop, which is the point: see "Score Break" below.

### WS3: Generation Fidelity

Findings: GEN-01 to GEN-11, ACT-05, ACT-06.

1. **Modern AST format** (GEN-01). Call `Prism::Translation::Parser::Builder.modernize` (or set the equivalent emit flags) in `SourceParser`. Then teach operators and filters the modern node types: `kwargs`, `procarg0`, `lambda`, `index`, `numblock`. This is a cross-cutting change; the WS0 fidelity check guards it.
2. **Range-level edits instead of subtree unparse.** An operator describes its mutation as `(source range, replacement text)` wherever possible: replace the operator token, the condition range, or the literal. A whole subtree is unparsed only when the operator must restructure it. This fixes:
   - **GEN-02:** the negated condition becomes `!(cond)`.
   - **GEN-03:** an `elsif` mutation replaces only the condition range.
   - **ACT-06:** a replacement that is a binary or lower-precedence node is parenthesised.
3. **Character-based offsets** (ACT-05). Splice with `String#[]` on character indices, or convert to byte offsets once and consistently.
4. **Encoding** (GEN-08). Read sources as UTF-8 and honour magic encoding comments.
5. **Operator and identity fixes:**
   - **GEN-04:** the identity includes the end offset and the original node's type and source.
   - **GEN-05:** subject patterns accept Ruby method-name syntax.
   - **GEN-06:** ReturnValue compares nodes with `equal?`.
   - **GEN-07:** StringLiteral skips `str` children of `regexp`, bracketless `array`, `dsym` and `xstr`.
   - **GEN-09:** RegexMutator keeps the dynamic parts and distinguishes `[^` from `^`.
   - **GEN-10:** the subject resolver handles `::Top`, `def Other.m`, `class << obj`, and `Struct`/`Data` blocks.
   - **GEN-11:** mutants are deduplicated per site on the mutated source text.

Acceptance:

- Every GEN reproduction is a passing spec.
- The fidelity check passes for all mutants of the dogfood run and the oracle corpus.

### WS4: Execution Efficiency and Robustness

Findings: EXE-03, EXE-05, EXE-07, EXE-09, EXE-10, EXE-11, EXE-12, EXE-13.

1. **Preloaded fork server per run** (EXE-13).
   - A long-lived child loads the integration environment (`spec_helper`/`rails_helper`, the test files of the run) once.
   - Mutant children are forked from it. They pay only for activation and the selected examples.
   - Baseline timing is taken in the same model, which makes the timeout calibration consistent (EXE-03).
   - Both RSpec and Minitest are covered. The existing `RailsEnvironmentPreloader` is the precedent.
2. **Timeout calibration** (EXE-03). Measure the wall time per test-file set in the fork-server model. Never cap the timeout below the measured baseline; warn instead.
3. **Output capture** (EXE-05). Do not wait for EOF without a bound. Drain the pipe once the child has been reaped and the process group cleaned up, or let children write to files.
4. **Process-group hygiene** (EXE-10, EXE-09). Clean up the process group after every normal exit in parallel mode as well. The INT trap signals the wakeup pipe.
5. **Per-test selection** (EXE-11, EXE-12).
   - Normalise the map keys with `File.expand_path` (a one-line fix with a large speed-up).
   - Then invert the selection: per-test coverage is the primary source of the candidate set; name matching is only a fallback when no per-test data exists.
6. **Flakiness policy** (EXE-07). Decision D3. Retrying survivors is the wrong default. The recommendation:
   - Detect flaky tests during the baseline by running the selected sets twice.
   - Re-run a kill only when every killing test is known to be flaky.
   - Report flaky tests explicitly.

Acceptance:

- On the slow-boot fixture, wall time per mutant no longer includes the boot, and no false `Timeout` occurs.
- The background-process fixture produces no `Timeout`.
- The dogfood wall time is reported before and after.

### WS5: Sound Verdict Reuse

Findings: REU-01 to REU-10.

1. **One reuse mechanism** (REU-01). Fold survivor-rerun skipping into `IncrementalFilter`, following ADR-11 (content fingerprints; git is never trusted as proof).
2. **One complete fingerprint for every reused status.** It covers:
   - the subject source
   - the content of every test in the *live* candidate set
   - the dependency globs (REU-04)
   - the effective configuration (operators, `test_excludes`, `coverage_criteria`)
   - the Henitai version and the recipe format version
3. **Explicit snapshot timing** (REU-02). `PerTestCoverage` exposes `reload`, and the runner reloads it after the Gate 0 join. Gate 1 uses its own pre-bootstrap reader.
4. **Git path normalisation** (REU-03). Use `--relative -z`, or resolve against `rev-parse --show-toplevel`; one normalised representation for all consumers. Use a merge-base diff (`REF...HEAD`) for `--since` (REU-10).
5. **Canonical report with per-file provenance** (REU-05, REU-06).
   - A run that covered a file completely replaces that file's entry wholesale.
   - The merge by ID applies only to partial runs.
   - Each file entry records the session and git SHA that produced it.
   - `--survivors-from` reads the per-file provenance.
6. **History store** (REU-07, REU-08, REU-09).
   - Use `mutant.stable_id`, and persist the replacement in the recipe.
   - Record trend runs only for authoritative runs.
   - Write the report before persisting history, and treat history failures as warnings.

Acceptance:

- Property-style spec: for scripted edit sequences on the oracle corpus (edit the source, add a test, edit a helper, change the config), the incremental verdicts equal the verdicts of a fresh full run.
- Every REU reproduction is a passing spec.

### WS6: Equivalence and Filters

Findings: FLT-01, FLT-03, FLT-04.

1. **Equivalence rules** (FLT-01).
   - Remove the rules that need type knowledge: right-literal `x || false` and `x && true`, `* 1` ↔ `/ 1` with an unknown receiver, `==` ↔ `eql?` with an unknown receiver, and `-0.0`.
   - Keep the left-literal forms.
   - Each remaining rule gets a spec documenting why it is sound.
2. **`ignore_patterns`** (FLT-03). Match only the node's own call or line range, and route matches through `StaticFilter` so they are reported as `Ignored`, not dropped.
3. **Sampling** (FLT-04). Sample across operators and positions with a fixed seed recorded in the report. Alternatively, rename the strategy to what it actually does (decision D5).

### WS7: Documentation and Communication

Findings: DOC-01, plus the consequences of all workstreams.

- Accept ADR-13 and mark ADR-04 superseded once WS2 lands. Update `docs/architecture/architecture.md` and `docs/plans/implementation_plan.md`, as the ADR maintenance rule requires.
- Fix the execution-model description in `AGENTS.md`.
- Add an ADR for the child status contract (WS1). Add an ADR for the fork-server execution model (WS4), or amend ADR-02.
- Write CHANGELOG entries that state the score break explicitly (see below).
- Add an entry to `MISTAKES.md`: the dogfood run hid ACT-01 because the activator's own namespace leaked into constant lookup.

## Sequencing

| Phase | Content | Depends on |
|---|---|---|
| A | WS0 (nets and baseline), then WS1 (status contract). Quick wins in parallel, each with its own spec: GEN-02, GEN-08, EXE-06, EXE-11 key normalisation, REU-03, REU-09. | — |
| B | WS2 (activation by `def`) and WS3 step 1 (modern AST), then the rest of WS3. | A, because the nets must exist first |
| C | WS4 (fork server, timeouts, selection, flakiness). | B, because activation after load is part of WS2 |
| D | WS5 (reuse) and WS6 (equivalence and filters). | A. Can run in parallel with B and C, but its acceptance specs need the oracle corpus. |
| — | WS7, alongside each phase. | — |

Each phase ends with:

- the full suite, RuboCop and Steep passing
- smoke runs
- dogfood MS/MSI and wall time re-measured
- the oracle rates recorded in the PR description

## Score Break

Phases A and B will **lower reported scores** for most projects, including
Henitai's own dogfood run, because false kills disappear and harness failures
leave the numerator. This is the intended outcome, not a regression.

- Release the result as a minor version (0.6.0) with a CHANGELOG section that explains the break.
- Keep thresholds in `.henitai.yml` unchanged until the new dogfood baseline is known. Then adjust them deliberately in a separate commit.

## Open Decisions

| ID | Question | Recommendation |
|---|---|---|
| D1 | Nesting for `def` injection: from the AST, or from the constant name? | **AST.** It is the only option that reproduces the original lexical scope exactly; it is the default unless rejected. |
| D2 | How to classify `SystemExit` raised during the test run. | `RuntimeError`: the suite did not complete, so no test verdict exists. |
| D3 | Flakiness policy. | Detect flaky tests in the baseline, and re-run kills only when they come from flaky tests (see WS4.6). |
| D4 | Fork server: a mandatory model, or opt-in at first? | Opt-in for one release behind a configuration flag, then the default. The oracle and smoke suites must pass in both modes. |
| D5 | Sampling: implement stratification, or rename the strategy? | Implement it. It is small and keeps the documented meaning. |
| D6 | Status contract transport: a status file or reserved exit codes? | A status file. It can carry counts and reasons, while exit codes alone cannot. |
