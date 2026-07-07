# Cross-Framework Comparison: Henitai vs. Stryker, PIT, mutmut, Infection

Date: 2026-07-06
Henitai version: 0.2.1
Scope: extends the 2026-07-02 parity comparison against `mutant` (Ruby) and
`cargo-mutants` (Rust) with four frameworks from other ecosystems. All
framework facts below were live-verified against current docs/repos on
2026-07-06 (versions in the matrix header); henitai claims were verified
against this repo's code, not its docs.

Companion documents:

- `docs/research/mutant_analysis.md` — deep dive on `mutant` (Ruby)
- `docs/research/stryker_analysis.md` — deep dive on Stryker (refreshed 2026-07-06)
- `docs/backlog/2026-07-02-*.md` — parity backlog from the mutant/cargo-mutants round
- `docs/backlog/2026-07-06-*.md` — backlog items derived from this round

## 1. Feature matrix

Versions: henitai 0.2.1 · mutant (2026-06 docs) · cargo-mutants (2026-06 docs)
· StrykerJS 9.6.1 · PIT 1.25.5 · mutmut 3.6.0 · Infection 0.34.0.

| Dimension | henitai | mutant (Ruby) | cargo-mutants | StrykerJS | PIT (Java) | mutmut (Python) | Infection (PHP) |
|---|---|---|---|---|---|---|---|
| Mutation backend | Prism AST, `define_method` injection | unparser AST, in-memory eval | source patch + rebuild | AST, mutant schemata (all mutants compiled in, runtime switch) | bytecode (ASM), rewrite in loaded class | libcst, trampoline schemata in `mutants/` copy | php-parser AST, stream-wrapper file swap |
| Isolation model | fork per mutant | fork per mutant | subprocess per build+test | long-lived worker child processes, sandbox dir copy | reused "minion" child JVMs | fork per mutant | subprocess per mutant |
| Operators | 19 classes, light/full sets | widest AST space (unparser) | operator-level since 23.12 (smaller set) | 15 categories | ~12 default, ~30 with experimental | fixed set, no on/off selection | 166 mutators, ~19 profiles |
| Per-test coverage selection | yes (line-level) | no (describe-prefix heuristic) | no (full suite per mutant) | yes (`perTest`, default) | yes (line coverage) | yes (trampoline hits + `max_stack_depth`) | yes (line coverage, mandatory) |
| Test ordering per mutant | kill-history first (`TestPrioritizer`) | — | — | — | fastest-first | fastest-first | fastest-first (bucket sort on JUnit timings) |
| Timeout strategy | fixed `mutation.timeout` (10s default) | fixed | **auto: 5× baseline, min 20s** | **auto: netTime×1.5 + 5000ms** | **auto: runtime×1.25 + 4000ms** | **auto: (est + 15s)×multiplier + CPU limit** | fixed seconds |
| Diff-based run (`--since`) | yes | yes | yes (`--in-diff`) | no (Stryker.NET only) | commercial (arcmutate) | no (content-hash based instead) | yes (`--git-diff-filter`, **`--git-diff-lines`**) |
| Cross-run result cache | **no** (SQLite history is trend-only) | session cache | `--iterate` | **`--incremental`** (killing-test-aware reuse) | **`withHistory`** (bytecode-hash reuse) | `.meta` files, per-function source hash | no |
| Survivor-only rerun | yes (`--survivors-from`, stable IDs) | partial | via `--iterate` | via incremental | via history | per-mutant rerun by name | no |
| Inline skip directives | `# henitai:disable` (line + method) | RSpec metadata | `#[mutants::skip]` | `// Stryker disable/restore`, per-mutator, reasons | commercial (`// NO PITEST`) | `# pragma: no mutate` + block/start-end | `@infection-ignore-all` (class/method/statement) + per-mutator regex ignores |
| Skipped mutants reported | yes (Ignored status) | — | — | yes (Ignored, with reason in report) | — | no (silently not generated) | no |
| Equivalence detection | **yes (AST-provable, conservative)** | no (light default set instead) | no | no | finally-block case only | no | no |
| Flaky-test retries | **yes (`max_flaky_retries`)** | no | no | no | no | no ("suspicious" status only) | no |
| Static-analysis mutant killing | no | no | no | no | no | **yes (`type_check_command`: mypy)** | **yes (`--static-analysis-tool`: PHPStan)** |
| Stryker JSON schema output | **yes (native)** | no | no | yes | no | no | yes (HTML logger uses same renderer) |
| HTML report | yes (mutation-testing-elements) | no | no | yes | yes | no (TUI instead) | yes |
| Dashboard upload | yes (Stryker Dashboard) | no | no | yes | no | no | yes (badge or full) |
| CI annotations (PR-inline) | backlog | no | yes (GitHub `::warning::`) | **no** | commercial | no | **yes (`--logger-github`, GitLab codequality)** |
| CI threshold gates | `thresholds.low` (exit 1) | — | exit codes | `thresholds.break` | `mutationThreshold` | exit code | **dual: `--min-msi` + `--min-covered-msi`** |
| Init wizard | `henitai init` (static template + TTY prompt) | no | no | interactive `stryker init` | no (build plugin) | no | interactive wizard on first run |
| Dry run / list mutants | `operator list` only | — | `--list` | `dryRunOnly` | `dryRun` param | — | `--show-mutations` (during run) |
| Sharding across machines | no | no | `--shard k/n` | no | no | no | no |
| Worker resource isolation hooks | backlog | fork hooks | — | — | — | — | `TEST_TOKEN` env var per thread |
| License | MIT | commercial outside OSS | MIT | Apache-2.0 | Apache-2.0 | BSD-3 | BSD-3 |

## 2. Architecture: henitai's ADR decisions vs. the field

### 2.1 Source AST vs. bytecode vs. schemata (ADR-01, ADR-04)

Three activation families exist in the field:

1. **Process-per-mutant with in-memory injection** — henitai (`define_method`
   in a fork), mutant, mutmut 2.x. Strongest isolation, highest per-mutant
   startup cost.
2. **Mutant schemata / mutation switching** — StrykerJS (all mutants compiled
   into instrumented source once, activated via a global variable, tests
   hot-reloaded), mutmut 3.x (trampolines dispatching on `MUTANT_UNDER_TEST`
   env var). One compile pass amortizes interpreter warm-up across all
   mutants; isolation is weaker (state can leak between mutants unless the
   runner restarts, cf. Stryker's `maxTestRunnerReuse` knob).
3. **Bytecode rewrite in reused workers** — PIT rewrites loaded classes inside
   long-lived minion JVMs; "orders of magnitude faster than starting a new
   jvm" (pitest FAQ).

Henitai's fork-per-mutant model (ADR-02/ADR-04) buys correctness: no mutant
can poison the next run, no sandbox directory copies (Stryker copies the
project to `.stryker-tmp` by default; Infection swaps files via a stream
wrapper). The cost is fork+require per mutant. The field's answer to that
cost is schemata — worth knowing as the ceiling for future performance work,
but it is a deliberate non-goal here as long as isolation is the priority.
mutmut 3.x is the interesting middle ground: schemata *plus* fork-per-mutant,
i.e. one codegen pass but still process isolation.

### 2.2 Per-test coverage selection (ADR-07)

Henitai's per-test line coverage is state of the art — it matches StrykerJS's
default (`coverageAnalysis: perTest`), PIT, mutmut 3.x, and Infection, and
beats mutant (describe-prefix heuristic) and cargo-mutants (full suite per
mutant). One refinement the field has that henitai lacks: **all four new
frameworks order the selected tests fastest-first** (PIT explicitly combines
coverage with test timings; Infection bucket-sorts on JUnit timings). Henitai
orders by kill-history (`TestPrioritizer`) — a different, complementary
heuristic. Combining both (kill-history first, runtime as tiebreaker) is a
cheap win; see backlog.

### 2.3 Timeouts

Henitai and Infection are the only tools in the matrix with a fixed manual
timeout. cargo-mutants (5× baseline), StrykerJS (netTime×1.5 + 5000ms), PIT
(×1.25 + 4000ms) and mutmut ((estimate + 15s) × multiplier, plus a CPU-time
limit via SIGXCPU) all derive it from measured baselines. This is now
**industry consensus**, confirmed across four independent implementations —
it strengthens `docs/backlog/2026-07-02-auto-calibrated-timeout.md`
considerably (filed as "Low" from cargo-mutants alone). mutmut's additional
CPU-time limit (catches busy loops even when wall-clock is inflated by slow
I/O) is a design detail worth stealing.

### 2.4 Incrementality (ADR-09)

The field splits incrementality into two orthogonal mechanisms; henitai has
one of them:

- **Scope reduction** (which subjects to mutate): henitai `--since`,
  Infection `--git-diff-filter`/`--git-diff-lines`, cargo-mutants
  `--in-diff`, Stryker.NET `--since`. Henitai is at parity here — notably
  *ahead* of StrykerJS (none), core PIT (moved to commercial arcmutate) and
  mutmut. Infection's `--git-diff-lines` (touched lines, not whole files) is
  finer than henitai's subject-level diff.
- **Verdict reuse** (skip re-testing unchanged mutants): Stryker
  `--incremental` (reuses a Killed verdict iff the killing test still exists
  unchanged), PIT `withHistory` (bytecode-hash invalidation, documented
  soundness caveats), mutmut (per-function source hash + git-based dependency
  change detection). **Henitai has no verdict reuse at all** — the SQLite
  `MutantHistoryStore` already persists per-mutant status history keyed by a
  stable identity (ADR-09), but it is only read for trend reporting, never to
  skip work. This is the single largest confirmed gap of this round (3 of 4
  frameworks have it) and the foundation already exists. See backlog.

Henitai's `--survivors-from` (stable-ID survivor rerun) remains ahead of
everything except what incremental caches subsume.

### 2.5 Status model and scoring (ADR-03)

- Henitai's Ignored-with-reporting for skipped mutants matches Stryker
  (Ignored status in the report) and beats mutmut/Infection (silently not
  generated) — auditability of what was skipped is preserved.
- Infection's dual CI gate (`--min-msi` vs `--min-covered-msi`) is the same
  dual-metric philosophy as henitai's MS/MSI pair; henitai gates only on MS
  (`thresholds.low`). Optional MSI gate noted in
  `docs/backlog/2026-07-02-exit-code-granularity.md`.
- PIT's `fullMutationMatrix` (record *all* killing tests, not first-kill) is
  research-grade opt-in there; henitai's `covered_by`/`killing_test` fields
  are structurally ready if that's ever wanted.

### 2.6 Where henitai is unique or ahead

Verified against all six comparison frameworks:

1. **Automatic equivalence detection** (`EquivalenceDetector`, AST-provable
   cases) — no other framework has any general mechanism; PIT handles one
   compiler-artifact case; mutant's answer is curating its default set.
2. **Flaky-test retries** (`max_flaky_retries` + >5% warning) — unique;
   mutmut's "suspicious" status is the closest, and it doesn't retry.
3. **Native Stryker JSON + HTML + Dashboard from a non-Stryker tool** — only
   Infection also does this; it makes henitai the de-facto Ruby member of
   the Stryker reporting ecosystem.
4. **OSS positioning**: git-diff runs, inline disable comments, and rich
   reporting are commercial add-ons in the Java world (arcmutate) and mutant
   is commercially licensed; henitai ships all of it MIT.
5. **Fork isolation without sandbox copies** — no `.stryker-tmp`-style
   project copy, no stream-wrapper interception; in-memory injection keeps
   the worktree untouched.

### 2.7 Where the field is ahead (verified gaps)

Ordered by how many frameworks confirm the pattern:

| Gap | Confirmed by | Henitai state | Action |
|---|---|---|---|
| Auto-calibrated timeout | 4 (cargo-mutants, Stryker, PIT, mutmut) | fixed value | existing ticket, evidence added |
| Verdict-reuse incremental cache | 3 (Stryker, PIT, mutmut) | history store is trend-only | **new ticket** |
| Fastest-first test ordering | 4 (Stryker*, PIT, mutmut, Infection) | kill-history ordering only | **new ticket** (*Stryker: implicit via runner) |
| Richer disable directives (per-operator, block scope, reasons) | 3 (Stryker, mutmut, Infection) | line + method scope, all-operator | **new ticket** |
| CI annotations | 2 (cargo-mutants, Infection) | none | existing ticket, evidence added |
| Dry-run / mutant listing without execution | 3 (Stryker `dryRunOnly`, PIT `dryRun`, cargo-mutants `--list`) | `operator list` only | **new ticket** |
| Static-analysis mutant killing | 2 (mutmut/mypy, Infection/PHPStan) | none | not filed — see below |
| Line-level diff scope (`--git-diff-lines`) | 1 (Infection) | subject-level `--since` | not filed (subject granularity is a deliberate design choice) |
| Sharding across machines | 1 (cargo-mutants) | none | not filed (previous round's decision stands) |

**Static-analysis killing, deliberately not filed:** mutmut kills mutants
that mypy rejects; Infection can use PHPStan. The Ruby analog would run
`steep check` against the mutated source before running tests. Deferred: this
repo's own Steepfile covers only 9 entry-point files, and RBS adoption in
target projects is too thin for the filter to pay for its complexity.
Revisit if RBS coverage in the Ruby ecosystem (or this repo) grows.

## 3. UX and onboarding

Time-to-first-report, live-checked flows:

| | Steps to first HTML/usable report |
|---|---|
| StrykerJS | `npm init stryker` (interactive wizard, detects runner) → `npx stryker run` → HTML report. **2 steps, best in class.** |
| Infection | `composer require` → run `infection` → first-run wizard writes `infection.json5` → report. ~3 steps. |
| PIT | add Maven plugin → one goal → HTML in `target/pit-reports`. 2 steps but manual XML config. |
| mutmut | `pip install` → 2-line `setup.cfg` → `mutmut run` → `mutmut browse` (TUI, no HTML). |
| henitai | `bundle add` → `henitai init` (static template + one TTY prompt) → `henitai run` → HTML in `reports/`. ~3 steps. |

Henitai's `henitai init` already exists (contrary to what a pure docs-read
suggests) but writes a static template; Stryker's and Infection's wizards
*detect* the environment (test runner, source dirs) and ask before writing.
Given henitai already auto-detects the integration at runtime, teaching
`init` to do the same detection is small. Two DX patterns worth copying
regardless of any ticket:

- **Stryker's `warnings.slow`**: the tool tells you when your config makes
  runs slow (e.g. coverage analysis off). Henitai equivalent: warn when
  `jobs: 1` on a multi-core machine, when per-test coverage is unavailable
  (so every mutant runs the full suite), or when `operators: full` meets a
  very large diff.
- **mutmut's `browse` TUI kill-loop**: survivors → inspect diff → jump to
  test → retest single mutant (`r`). Henitai's HTML report is read-only;
  `--survivors-from` is the batch analog but there is no single-mutant
  interactive loop. Not filed as a ticket (large surface, unclear payoff vs.
  HTML report) — recorded here as a direction.

Docs positioning: henitai's arc42 + 10 ADRs + research summaries is the
deepest *architecture* documentation in this comparison (nothing else comes
close; mutmut's ARCHITECTURE.rst is the runner-up). The inverse holds for
*user-facing* docs: Stryker and Infection have polished doc sites with
per-topic guides and playgrounds; henitai has README + CLAUDE.md. As adoption
grows, a user-guide split (getting started / configuration / CI recipes /
disable directives) mirroring Stryker's structure is the template to follow.

## 4. Backlog derivation

New tickets filed from this round (see files for full plans):

- `docs/backlog/2026-07-06-incremental-verdict-cache.md` — reuse
  `MutantHistoryStore` verdicts to skip unchanged mutants (Stryker
  `--incremental` / PIT `withHistory` / mutmut hashing).
- `docs/backlog/2026-07-06-runtime-aware-test-ordering.md` — extend
  `TestPrioritizer` with fastest-first tiebreaker (PIT/Infection/mutmut).
- `docs/backlog/2026-07-06-dry-run-mode.md` — `--dry-run` to list generated
  mutants without executing tests (Stryker `dryRunOnly`, PIT `dryRun`,
  cargo-mutants `--list`).
- `docs/backlog/2026-07-06-richer-disable-directives.md` — per-operator
  lists, block scope, reasons for `# henitai:disable` (Stryker
  disable/restore, mutmut block pragmas, Infection statement scope).

Existing tickets extended with cross-framework evidence (in place):

- `2026-07-02-auto-calibrated-timeout.md` — now 4-framework consensus;
  Stryker/PIT/mutmut formulas added.
- `2026-07-02-ci-annotation-reporter.md` — Infection `--logger-github` +
  GitLab codequality precedent; StrykerJS has *none* (differentiator).
- `2026-07-02-exit-code-granularity.md` — Infection's dual
  `--min-msi`/`--min-covered-msi` gate noted as related option.
- `2026-07-02-parallel-worker-resource-isolation-hooks.md` — Infection's
  `TEST_TOKEN` per-thread env var as a lighter-weight design alternative.
