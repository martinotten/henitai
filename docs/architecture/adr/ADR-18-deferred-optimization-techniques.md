# ADR-18: Defer Five Optimization Techniques From the Literature

**Status:** Accepted
**Date:** 2026-11-12

## Context

A survey of optimization techniques for mutation testing (generation,
selection, execution; Offutt & Untch's "do fewer / do smarter / do faster")
compared the literature and other frameworks (PIT, Stryker, Infection,
mutmut, cargo-mutants, mutant, Google's and Meta's in-house tools) with
henitai's pipeline.

Henitai already implements most of the established techniques:
coverage-based test selection, kill-history plus fastest-first ordering,
arid-node filtering, stillborn filtering, conservative equivalence
detection, stratified sampling, `--since`, sound verdict reuse (ADR-11),
in-process `def` injection (ADR-13), the fork server (ADR-15), calibrated
timeouts and survivor reruns.

The remaining techniques split into three groups:

- **Clear and cheap, scheduled:** fail-fast inside the mutant child
  (`docs/backlog/2026-11-12-child-fail-fast.md`), cross-machine sharding
  (`docs/backlog/2026-11-12-ci-sharding.md`) and the warm CI verdict cache
  (`docs/backlog/2026-07-13-ci-warm-verdict-cache.md`).
- **Unclear yield, measured first:** Trivial Compiler Equivalence on YARV
  instruction sequences (`docs/backlog/2026-11-12-iseq-trivial-compiler-equivalence.md`).
- **Deferred:** the five techniques below. They are either already covered
  for the most part, conflict with a standing decision, or cost far more
  than their expected benefit.

Two invariants decide most of the cases below:

1. **A verdict is sound or absent** (ADR-11, ADR-14). Henitai never reports
   a verdict it cannot back with a test run of exactly the reported mutation.
   Techniques that approximate a verdict to save time are therefore off the
   table as scoring inputs.
2. **One owner per concern, no parallel paths** (`CODE_PRINCIPLES.md` rules
   7–9, "No Parallel Implementations" in `AGENTS.md`). A technique that adds a
   second way to activate or execute mutants must replace the existing path,
   not sit next to it.

## Decision

The following techniques are deferred. Each one has a revisit trigger.
Without that trigger, a proposal to implement it should point to this ADR
instead of reopening the analysis.

### 1. Mutant schemata (mutation switching)

All mutants of a method would be compiled into one `def` with a runtime
switch (Untch et al. 1993; Stryker, mutmut 3). A child process could then
test several mutants without reloading the test files.

- The main saving of schemata is avoiding a rebuild and reboot per mutant.
  In-memory `def` injection (ADR-13) already avoids the rebuild, and the
  fork server (ADR-15) already avoids the reboot. What remains is loading the
  selected spec files per child.
- The schema source is not the reported mutation. `FidelityCheck` (ADR-14)
  compares the activation source with the reported mutation exactly. A
  switch-based activation would need a new fidelity argument: the inactive
  branches must have no effect, including through `defined?`, `binding`,
  `__method__`, `instance_method(...).source` and constant lookup.
- Several mutants per child break process isolation per mutant (ADR-02),
  or need state reset between them. That is exactly the leakage the fork
  model exists to avoid.
- It would be a second activation path next to `DefInjection`, which the
  rules against parallel implementations forbid unless it replaces the
  existing path.

**Revisit when** profiling a fork-server run on a real project shows that
loading spec files makes up more than half of the per-mutant wall-clock
time, after fail-fast has landed.

### 2. Per-line mutant cap or "review mode"

Google's diff-based review tool emits at most one mutant per line to keep
review comments readable.

- ADR-08 removed henitai's `max_mutants_per_line` cap, because every other
  framework emits every mutation and the cap made scores depend on internal
  priority order. A review mode would reintroduce that cap.
- The use case (a few readable findings on a pull request) is already
  served by `--since`, the CI annotation reporter and `--survivors-from`.
- A cap changes the score's denominator, so it would need its own reporting
  semantics. That is a product decision, not an optimization.

**Revisit when** there is a concrete PR-workflow requirement that
`--since` plus annotations cannot meet. Treat it as a reporter-level
presentation filter, never as a generation-level cap, so that ADR-08 still
holds.

### 3. Subsumption and dominator mutants

Redundant mutants (those subsumed by another mutant) would be removed to
compute a less inflated score (Kurtz, Ammann et al.).

- Subsumption needs the full kill matrix: every test against every mutant.
  Henitai deliberately avoids building it. Coverage selection, kill-first
  ordering and (soon) fail-fast all stop at the first kill.
- Building the matrix would multiply run time by the number of covering
  tests. Static approximations of subsumption are research prototypes and
  not sound.
- The benefit is the quality of the score, not run time.

**Revisit when** a research or reporting need for the full kill matrix
appears on its own merits. The matrix would then come for free, and
dominator analysis would be a pure post-processing step on the report.

### 4. Test-impact analysis beyond line coverage

Tests could be selected through a dependency graph (files, constants,
dynamic dispatch) instead of per-test line coverage, to catch tests that
affect a mutant without executing its line.

- A test can only observe a mutation if the mutated code executes during
  the test. Per-test line coverage records exactly that execution. The
  remaining gaps are coverage-collection gaps: code run at load time, code
  run in forked or threaded sub-processes, and `eval`. Fixing those is a
  coverage concern, not a selection concern.
- The name-matching fallback already covers subjects without per-test
  data. `rake oracle` measures false survivors on a corpus with known
  verdicts and would show missed killers.

**Revisit when** `rake oracle` or a user report shows a false survivor
caused by a killing test that the per-test map does not select.

### 5. Weak mutation, firm mutation and ML-predicted verdicts

Weak and firm mutation only check whether the program state differs at or
near the mutation point. Predictive mutation testing (Zhang et al. 2016) and
LLM-based approaches estimate a verdict without running the tests.

- None of these produces a verdict caused by a test failing on exactly the
  reported mutation. They contradict ADR-14 and the "sound or absent" rule
  of ADR-11 directly.
- Using them only as a pre-filter (skip mutants predicted to be killed)
  would turn false predictions into false kills, which `rake oracle` is
  built to prevent.

**Revisit when** a use case for a separate, non-scoring advisory
signal comes up, for example a fast "likely weak spots" hint. It must never
feed MS, MSI, the history store or verdict reuse.

### Not considered further: split-stream execution

Running the shared prefix of a test once and forking only at the mutation
point (King & Offutt 1991; AccMut, Wang et al. 2017) needs control over the
interpreter's state at an arbitrary instruction. In CRuby that would mean
changing the VM. The fork server is the practical approximation at the
process boundary.

## Consequences

- The optimization backlog stays focused on fail-fast, sharding, the warm
  CI cache and the TCE measurement.
- Each deferred technique has a stated, observable revisit trigger. Proposals
  that do not meet it are answered with a pointer to this ADR.
- The "sound or absent" rule (ADR-11, ADR-14) is now stated as an explicit
  exclusion criterion for approximate-verdict techniques.
- No code, configuration or CLI changes.

## Execution paths

None. This ADR adds no mode, option or code path. It records why five
candidate paths (schema activation, review-mode capping, kill-matrix runs,
graph-based selection and approximate verdicts) are not added.
