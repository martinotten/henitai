# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-04-13

### Fixed
- Coverage formatter specs now honor `HENITAI_REPORTS_DIR`, so the baseline
  coverage bootstrap no longer fails when the suite runs under the mutation
  runner's configured reports directory

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

[Unreleased]: https://github.com/martinotten/henitai/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/martinotten/henitai/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/martinotten/henitai/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/martinotten/henitai/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/martinotten/henitai/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/martinotten/henitai/releases/tag/v0.1.0
