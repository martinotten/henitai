# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-07-14

### Added
- `hard` operator set (`mutation.operators: hard` / `--operators hard`), a
  strict superset of `full` for usually-unkillable mutations (ADR-12):
  currently `EqualityIdentityOperator` and the new `HashKeyType`
  (`{ a: 1 }` -> `{ "a" => 1 }`) — framework key normalization (e.g.
  ActiveRecord `order`/`where`) makes key-type mutants frequently equivalent
- `HashLiteral` gains per-pair removal (`{ a: 1, b: 2 }` -> `{ b: 2 }`);
  single-pair hashes and double-splat entries are skipped

### Changed
- `full` now means "usually killable": the symbol-key -> string-key mutation
  moved from `HashLiteral` into the new hard-set `HashKeyType`, and
  `EqualityIdentityOperator` moved from `full` to `hard` — `full` runs emit
  fewer, higher-signal mutants

## [0.3.1] - 2026-07-13

### Fixed
- Per-mutant log capture no longer crashes with
  `Encoding::UndefinedConversionError` when the host app sets
  `Encoding.default_internal` (as Rails test environments do) and a child
  process prints multibyte output: the capped log streams are opened in
  binary mode, so pipe chunks are written byte-for-byte. Also keeps a
  multibyte character split across drain chunks (or truncated at the cap)
  from corrupting the file.

### Changed
- `--since REF` now includes the working tree: tracked files with
  uncommitted changes and untracked files count as changed, matching what
  actually gets tested. Previously only committed changes in `REF..HEAD`
  were considered, so pre-commit runs silently selected nothing.
- `--since REF` is test-aware: a changed test file selects the source files
  it covers, using the per-test coverage map from the previous run
  (`henitai_per_test.json`). Editing only a test now re-tests the subjects
  that test can kill. First run without a map: no expansion.
- An empty `--since` run now says why: the terminal summary appends
  `No mutants: no configured source files changed since REF.` instead of
  printing an unexplained all-zero table. `Result` gained a `since`
  attribute to carry the scope.

## [0.3.0] - 2026-07-13

### Added
- `henitai run --incremental`: verdict reuse from the history store. Killed
  verdicts are reused when the subject's source and every covering test file
  are byte-identical to what was recorded; Survived verdicts are additionally
  gated on the live per-test covering set (membership and content) plus a
  run-level dependency fingerprint over spec helpers, support files,
  fixtures/factories, `Gemfile.lock`, `.henitai.yml`, and `.rspec` (ADR-11).
  Reused mutants carry `fromCache: true` in the JSON report; the terminal
  prints the reused split and an executed-only MS/MSI line. `--force` bypasses
  reuse; every doubt (missing per-test map, ambiguous ids, legacy rows,
  timeout/error verdicts) resolves to re-execution
- Canonical report merge: scoped and partial runs (`--since`, subject
  patterns, `--survivors-from`) merge into `reports/mutation-report.json`
  keyed by `stableId` instead of overwriting it; full runs still replace it
- Checkpoint reporting: long runs persist partial JSON/HTML results
  incrementally, so a crashed or aborted run keeps its finished verdicts
- Reports-directory locking: concurrent runs against the same `reports_dir`
  fail fast with `ConcurrentRunError`; when the recorded owner pid is dead the
  error names the likely orphaned child and the `lsof` command to find it
- `henitai run --dry-run`: list the post-filter mutant set without executing
  any tests (always exits 0)
- `--strict-exit-codes` (opt-in): exit 3 when mutants timed out, 4 on
  runtime/compile errors; precedence 2 > 3 > 4 > 1 > 0
- Auto-calibrated per-mutant timeout from the measured test baseline
  (`--timeout-multiplier`, default 3.0) when `mutation.timeout` is unset
- Runtime-aware test ordering: per-test durations from the coverage pass
  prioritize fast tests within a mutant run
- Richer `# henitai:disable` directives: operator lists, reasons, and
  `begin`/`end` regions
- GitHub Actions annotation reporter
- `HENITAI_WORKER_SLOT` environment variable for per-worker resource
  isolation in parallel runs
- `EqualityIdentityOperator`: the hard-to-kill `==`/`eql?`/`equal?` pairing
  moved out of the default light set into its own operator (ADR-10)

### Fixed
- Mutants in `module_function` modules were unkillable: `module_function`
  copies the method onto the module's singleton and activation only replaced
  the instance side, so callers kept running original code and every such
  mutant falsely survived. Activation now re-copies the injected method when
  the pre-injection shape proves a `module_function` copy
- Per-test coverage attributed each line only to the first test that executed
  it; the map now credits every test whose run increments a line's hit count,
  fixing silent test under-selection (a latent false-Survived risk)
- Coverage freshness now watches the dependency file set as well: edits are
  detected by mtime, deletions via a recorded path manifest
  (`henitai_dependency_manifest.json`); `henitai clean` removes the sidecar
- Stable-id collisions between same-signature mutants are disambiguated with
  a site offset (`legacyStableId` is emitted temporarily so scoped runs
  replace pre-offset canonical entries instead of duplicating them)
- Child stdout/stderr capture is capped (`max_log_bytes`) so runaway mutants
  cannot exhaust memory on long runs
- Flaky-retry counter no longer inflates when a respawned child fails again

### Changed
- Terminal reporter renders original nodes from their source slice and reuses
  a memoized unparse of the mutated node shared with the JSON reporter
  (a dogfood profile spent 27% of wall time re-unparsing survivors)
- The survivor dependency fingerprint prunes generated artifact trees
  (fixture projects' `reports/`, `coverage/`, `mutation-logs/`) during the
  scan — only on evidence of actual output, never by directory name alone —
  cutting fingerprint time from ~0.7s to ~1.5ms and keeping smoke runs from
  invalidating survivor reuse
- Mutant children no longer emit unconditional debug lines, coverage-formatter
  warnings for deliberately suppressed coverage, or rspec-mocks `__send__`
  redefinition warnings into their logs

### Internal
- Architecture documentation gained §8.11 (incremental verdict reuse) and
  ADR-11 (content-fingerprint verdict reuse, not git scoping); new backlog
  tickets for CI warm verdict cache, child null formatter, and auto-`--since`
- Spec writes into the repository checkout are rejected wholesale — mutants
  that reroute CLI dispatch into `init` now count as kills instead of
  littering the working tree
- `.henitai-pi-agent/` session transcripts untracked

## [0.2.1] - 2026-06-25

### Fixed
- `henitai run` now exits 0 when a run evaluates no valid mutants, instead of
  failing a CI gate on a vacuous result
- Flaky-retry counts are now recorded on the parallel execution path (they were
  always reported as 0 regardless of actual retries)

### Changed
- `Result` and `Reporter::Json` take their IO as an injected dependency,
  restoring the domain/infrastructure boundary (no public API change)
- Decomposed the monolithic `integration.rb` into single-responsibility files
  and reparented `Integration::Minitest` off `Rspec` onto a shared
  `MutantRunSupport` mixin; restored class-size discipline across the codebase
- Narrowed broad rescues in `safe_unparse` and per-test coverage snapshotting

### Internal
- De-mocked runner specs, added `process_wakeup` and helper coverage, and
  removed sleep- and chdir-based flakiness from the suite
- Enabled full-operator dogfooding configuration and isolated the
  `minitest_simplecov` spec
- Reconciled README and consolidated plan-tree documentation

## [0.2.0] - 2026-04-30

### Added
- `--survivors-from <path>` flag on `henitai run` for survivor-only reruns:
  re-execute only the mutants that survived a prior full run without re-running
  the whole suite
- `SurvivorLoader` reads a Stryker-compatible JSON report and extracts survivor
  IDs, per-survivor coverage maps (`coveredBy`), and the anchoring git SHA
- `SurvivorSelector` filters the current mutant set to the survivor subset; emits
  a drift warning when more than 50% of loaded survivors are unmatched (source
  changed significantly since the prior run)
- `SurvivorTestFilter` skips survivors whose covering tests are unchanged since
  the prior report's git SHA, marking them `:survived` immediately without
  execution — same safety logic as StrykerJS incremental mode
- `MutantIdentity` module: stable SHA256 identity computed from expression,
  operator, description, location, and mutation signature; shared by
  `MutantHistoryStore` and `Mutant#stable_id`
- `Mutant#stable_id` exposes the stable identity; emitted as `stableId` in the
  JSON report so survivor reports remain useful across commits
- `Result` carries `session_id` (UUID) and optional `git_sha` (HEAD SHA at
  report time); both emitted in the Stryker-compatible JSON as `sessionId` /
  `gitSha`
- `Reporter::Json` writes an immutable per-session snapshot alongside the
  canonical report at `reports/sessions/<session_id>/mutation-report.json`,
  giving `--survivors-from` a stable reference path across runs
- `GitDiffAnalyzer#head_sha` — returns the current HEAD SHA; `nil` when git is
  unavailable (conservative fallback: all survivors are executed)
- `ProcessWorkerRunner` — flat process-slot scheduler for parallel mutant
  execution: each slot owns one OS process, slots are refilled as children
  finish, no thread per child
- Interrupt handling, spawn failure isolation, and in-slot retry added to
  `ProcessWorkerRunner` (PR 6)
- Timeout precision and two-phase process-group cleanup in
  `ProcessWorkerRunner` (PR 5)
- x86_64 platform added to gem platform list

### Changed
- JSON mutation report vendor extension now always includes `sessionId`
  (and `gitSha` when available) to support survivor-only reruns
- Terminal reporter labels partial reruns as "Partial survivor rerun" and
  shows matched / unmatched / skipped-by-diff counts
- History store skips `runs` row insertion for partial reruns to avoid
  distorting trend analytics; per-mutant `current_status` upsert still runs
- CLI exits 0 for partial reruns with a printed warning; threshold comparison
  is skipped (applying a partial score to a CI gate is misleading)
- `StaticFilter` merges per-test coverage into standard coverage so
  `coveredBy` data is available to both RSpec and Minitest survivor reports
- `.henitai.yml` default: operators set to `light`, timeout lowered to 10 s,
  `max_flaky_retries: 3` added

### Fixed
- Minitest autorun hook suppressed in mutation child processes to prevent
  spurious re-runs of the full suite inside each fork
- Coverage bootstrap RSpec subprocess ARGV leakage resolved — child processes
  no longer inherit the parent's `--format` / file arguments
- Survivor rerun state preserved across RSpec execution (was reset on each
  subprocess boot)
- `--survivors-from` now respects dirty worktrees: coverage and source file
  state are read from the working tree, not the index
- Recipe fast path skipped when source files changed since the cached run,
  preventing stale cache hits after edits

### Performance
- File discovery cached in the integration layer; repeated calls within one
  run no longer re-scan the filesystem
- Polling sleep removed from the scheduler hot loop; slots are refilled
  event-driven on child exit

## [0.1.10] - 2026-04-16

### Fixed
- RuboCop `RSpec/MultipleExpectations` offenses in `coverage_formatter_spec` and
  `per_test_coverage_collector_spec` resolved by splitting each two-assertion
  example into focused single-expectation examples

## [0.1.9] - 2026-04-16

### Fixed
- SimpleCov is now suppressed during Minitest mutant child runs: `SimpleCov.start`
  is turned into a no-op before test files are required, eliminating the
  "Stopped processing SimpleCov as a previous error has been detected" warning
  and avoiding unnecessary coverage instrumentation overhead in every mutant fork

## [0.1.8] - 2026-04-16

### Added
- Minitest integration now supports per-test coverage: a `MinitestCoverageReporter`
  snapshots `Coverage.peek_result` after each test and writes `henitai_per_test.json`,
  enabling targeted mutation runs that only execute the tests covering the mutated lines —
  the same efficiency that was previously available only to RSpec projects

### Fixed
- RSpec integration now respects `--exclude-pattern` entries in `.rspec` so excluded
  spec files are not passed to the runner during mutation runs
- Per-test source file filter corrected to check only the project-relative path prefix
  rather than scanning the full absolute path, preventing false exclusions when the
  project lives under a directory whose path contains `/spec/` or `/test/`

## [0.1.7] - 2026-04-14

### Added
- Committed integration smoke projects for RSpec and Minitest, runnable via
  `bundle exec rake smoke:integration:all`, to exercise `henitai` against
  small real projects that depend on the local source checkout

### Fixed
- Child-process stdout/stderr restoration after captured test runs now keeps
  the standard streams usable, preventing passing mutant executions from being
  misclassified because the child exited with a closed stdio handle
- Root `bundle exec rspec` no longer picks up the committed smoke fixture spec
  files, and `spec/spec_helper.rb` no longer auto-requires support specs during
  suite boot

## [0.1.6] - 2026-04-14

### Fixed
- Minitest is no longer required eagerly when `henitai/integration` loads, so
  projects that do not include Minitest in their bundle can still boot and use
  non-Minitest integrations without a parent-process `LoadError`

## [0.1.5] - 2026-04-14

### Fixed
- Steep type errors in `Runner` after removing targeted-run bootstrap scoping:
  updated `bootstrap_mutants` RBS signature to match the new single-argument
  form and removed stale signatures for `refresh_coverage_for_targeted_run`,
  `scoped_bootstrap_test_files`, `targeted_run?`, and `retry_full_bootstrap?`
- `RSpec/ExampleLength` offense in `coverage_bootstrapper_spec.rb` — extracted
  workspace setup and report writing into helper methods

### Changed
- Targeted-run coverage bootstrap no longer scopes the initial run to the
  subject's test files; the full suite is always used for the baseline,
  trading a minor performance optimisation for reliability

## [0.1.4] - 2026-04-14

### Fixed
- `StringLiteral` operator no longer generates no-op mutations where the
  replacement equals the original value (e.g. the spurious `"" → ""` mutant
  that was emitted for methods already returning an empty string literal)
- Terminal diff output now uses `display_unparse` for string literal nodes,
  making whitespace-only mutations unambiguous in the report
  (e.g. `""`, `" "`, and `"\n"` are now visually distinct)
- Targeted coverage bootstrap (`--since` / explicit subjects) now correctly
  retriggers a full suite run when the scoped bootstrap does not produce
  coverage for all configured source files; previously the run could raise
  `CoverageError` even though a fallback was available
- Coverage formatter specs now honor `HENITAI_REPORTS_DIR`, so the baseline
  coverage bootstrap no longer fails when the suite runs under the mutation
  runner's configured reports directory

### Changed
- `ScenarioExecutionResult.build` factory method consolidates status and
  exit-status derivation that was previously spread across `Integration`,
  reducing the mutation surface of the value object

## [0.1.3] - 2026-04-13

### Added
- Four new mutation operators: `UnaryOperator` (negates boolean and numeric
  unary expressions), `UpdateOperator` (swaps `+=`/`-=`/`*=` and targets
  compound-assignment nodes), `RegexMutator` (replaces regex literals with
  never-match and always-match equivalents), and `MethodChainUnwrap` (removes
  one step from a method chain to expose intermediate values)
- `AvailableCpuCount`: container-aware CPU detection via cgroup v1/v2 and
  cpuset files; the execution engine uses this to cap the default worker count
  to the number of CPUs actually available to the process
- `PerTestCoverageSelector`: narrows the candidate test set for each mutant
  using per-test line-coverage data, reducing the number of processes forked
  for targeted runs
- `CoverageReportReader`: dedicated reader for `.resultset.json` and
  `henitai_per_test.json`, giving `StaticFilter` and `PerTestCoverageSelector`
  a single, tested JSON-parsing seam
- Equivalence detection now covers logical identity patterns: `false || x`,
  `x || false`, `true && x`, `x && true` are suppressed as equivalent mutants

### Changed
- Per-line mutation cap (`max_mutants_per_line`) removed from the generator,
  configuration schema, and validator — see ADR-08. All syntactically valid
  mutations on a line are now generated unconditionally
- Default execution mode switched to linear (single-worker) as the
  conservative, predictable baseline; parallel mode is still available via
  configuration
- `ParallelExecutionRunner` and `RspecProcessRunner` extracted from
  `ExecutionEngine` and `Integration::Rspec` respectively, separating
  orchestration concerns from integration concerns
- `wait_with_timeout`, `cleanup_process_group`, and `reap_child` promoted to
  public helpers on `Integration::Base` so `RspecProcessRunner` can call them
  without reflection

### Performance
- Coverage bootstrap freshness check: the baseline RSpec run is skipped when
  `.resultset.json` is newer than every watched source and test file,
  eliminating ~83 % of bootstrap wall time on repeated runs within a session
- Overlapped bootstrap: the baseline run starts in a background thread
  immediately after subject resolution and runs concurrently with mutant
  generation; only Gate 3 (StaticFilter) blocks on completion
- Subject-scoped bootstrap: for targeted runs (`--since` / explicit subjects),
  only the tests that cover the selected subjects are bootstrapped; falls back
  to the full suite when the scoped set is empty
- Automatic retry of the full bootstrap when a scoped bootstrap yields no
  coverage candidates for a targeted run
- `SourceParser` parse cache: each source file is parsed at most once per
  pipeline run, removing duplicate parse calls between `SubjectResolver` and
  `MutantGenerator`
- `StaticFilter` path cache: `File.realpath` is called at most once per unique
  path per filter invocation
- `MutantGenerator::SubjectVisitor`: subject range boundaries are pre-computed
  at visitor construction time, eliminating one `Range` allocation per visited
  AST node

### Fixed
- Mutant child processes now run in isolated process groups (`setpgid`);
  `cleanup_process_group` sends `SIGTERM` to the entire group on timeout or
  error, preventing orphaned subprocesses
- Pipeline error handling hardened across `CoverageBootstrapper`,
  `ExecutionEngine`, `Runner`, and `SubjectResolver`: errors are surfaced
  with a structured result instead of being swallowed silently
- Report score thresholds now reflect the final aggregated result correctly
- Three regressions introduced during the performance work resolved (path
  normalisation, scoped bootstrap fallback, overlapped thread join order)
- RBS/Steep signatures updated for bootstrap options, integration helpers,
  result types, and the new operators

## [0.1.2] - 2026-04-07

### Added
- Method coverage is now enabled in both RSpec and Minitest bootstraps, and
  the static filter merges method-level coverage into the line map

### Fixed
- Coverage baseline regeneration now happens on every `henitai run`, so stale
  coverage state does not leak between runs
- Coverage handling now accepts symbol-keyed `Coverage.peek_result` output and
  canonicalizes source file keys in `henitai_per_test.json`
- Integration child processes isolate stdio correctly, and the integration
  pause signature was restored so captured output stays stable
- Coverage checks now consider the full mutant line range instead of only the
  starting line
- `Henitai::Mutant::Activator` now rewrites heredoc-backed method bodies from
  source slices instead of unparsing the whole body, eliminating timeouts on
  HTML reporter mutants
- `henitai run -v` now stops before the run pipeline starts

## [0.1.1] - 2026-04-03

### Added
- Minitest integration for Rails projects: injects SimpleCov for coverage
  collection, sets `RAILS_ENV=test` and `PARALLEL_WORKERS=1` in the baseline
  subprocess, preloads `config/environment.rb` before mutant activation, adds
  `test/` to `$LOAD_PATH` before forking, and excludes `test/system/` by default
- `simplecov` runtime dependency (required by the Minitest integration)

### Fixed
- `rspec/core` was unconditionally required at load time, causing a `LoadError`
  in projects that do not have RSpec installed — now loaded lazily only when the
  RSpec integration is used
- Coverage path normalisation now uses `File.realpath` so symlinked temp
  directories on macOS no longer cause false no-coverage results

## [0.1.0] - 2026-03-01

### Added
- Initial gem scaffold with Ruby 4.0.2 support
- Dev Container configuration (official `ruby:4.0.2-alpine` base image, Codex CLI preinstalled)
- CI pipeline (RuboCop + RSpec + incremental mutation testing on PRs)
- `.henitai.yml` configuration schema
- Module structure: `Configuration`, `Subject`, `Mutant`, `Operator`, `Runner`, `Reporter`, `Integration`, `Result`
- CLI critical path: `henitai run` now executes the full pipeline, supports `--since`, returns CI-friendly exit codes, and `henitai version` prints `Henitai::VERSION`
- RSpec per-test coverage output: `henitai/coverage_formatter` now writes `coverage/henitai_per_test.json`

[Unreleased]: https://github.com/martinotten/henitai/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/martinotten/henitai/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/martinotten/henitai/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/martinotten/henitai/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/martinotten/henitai/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/martinotten/henitai/compare/v0.1.10...v0.2.0
[0.1.10]: https://github.com/martinotten/henitai/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/martinotten/henitai/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/martinotten/henitai/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/martinotten/henitai/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/martinotten/henitai/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/martinotten/henitai/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/martinotten/henitai/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/martinotten/henitai/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/martinotten/henitai/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/martinotten/henitai/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/martinotten/henitai/releases/tag/v0.1.0
