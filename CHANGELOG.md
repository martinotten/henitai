# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial gem scaffold with Ruby 4.0.2 support
- Dev Container configuration (official `ruby:4.0.2-alpine` base image, Codex CLI preinstalled)
- CI pipeline (RuboCop + RSpec + incremental mutation testing on PRs)
- `.henitai.yml` configuration schema
- Module structure: `Configuration`, `Subject`, `Mutant`, `Operator`, `Runner`, `Reporter`, `Integration`, `Result`

[Unreleased]: https://github.com/martinotten/henitai/commits/main
