# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-04-07

### Fixed
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

[Unreleased]: https://github.com/martinotten/henitai/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/martinotten/henitai/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/martinotten/henitai/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/martinotten/henitai/releases/tag/v0.1.0
