# frozen_string_literal: true

require_relative "lib/henitai/version"

Gem::Specification.new do |spec|
  spec.name    = "henitai"
  spec.version = Henitai::VERSION
  spec.authors = ["Martin Otten"]
  spec.email   = ["martin.otten@innoq.com"]

  spec.summary     = "Mutation testing for Ruby — Stryker-compatible"
  spec.description = <<~DESC
    Hen'i-tai (変異体) is a mutation testing framework for Ruby 4+.
    It produces Stryker-compatible mutation-testing-report-schema JSON,
    integrates with the Stryker Dashboard, and ships with a standalone
    HTML report powered by mutation-testing-elements.

    A free, open-source alternative to the mutant gem — with built-in
    cost-reduction strategies, per-test coverage analysis, and CI/CD
    integration out of the box.
  DESC

  spec.homepage = "https://github.com/martinotten/henitai"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata = {
    "bug_tracker_uri"   => "https://github.com/martinotten/henitai/issues",
    "changelog_uri"     => "https://github.com/martinotten/henitai/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/martinotten/henitai/blob/main/README.md",
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/martinotten/henitai",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "assets/**/*",
    "LICENSE",
    "README.md",
    "CHANGELOG.md"
  ]

  spec.bindir        = "exe"
  spec.executables   = ["henitai"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "parser",   "~> 3.3"   # Ruby AST parsing
  spec.add_dependency "unparser", "~> 0.6"   # AST → source code reconstruction

  # Development dependencies (via Gemfile)
end
