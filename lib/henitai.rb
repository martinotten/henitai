# frozen_string_literal: true

require_relative "henitai/version"

# Hen'i-tai (変異体) — Mutation testing for Ruby
#
# Usage:
#   henitai run --use rspec 'MyNamespace*'
#   henitai run --since HEAD~1 'MyClass#my_method'
#
module Henitai
  HISTORY_STORE_FILENAME = "mutation-history.sqlite3"

  # Raised when the framework encounters a configuration error
  class ConfigurationError < StandardError; end

  # Raised when a subject expression cannot be resolved
  class SubjectNotFound < StandardError; end

  # Raised when coverage data cannot be bootstrapped or validated.
  class CoverageError < StandardError; end

  autoload :Configuration, "henitai/configuration"
  autoload :CoverageBootstrapper, "henitai/coverage_bootstrapper"
  autoload :CoverageReportReader, "henitai/coverage_report_reader"
  autoload :PerTestCoverageSelector, "henitai/per_test_coverage_selector"
  autoload :Subject, "henitai/subject"
  autoload :Mutant, "henitai/mutant"
  autoload :Operator, "henitai/operator"
  autoload :Operators, "henitai/operators"
  autoload :SourceParser, "henitai/source_parser"
  autoload :SubjectResolver, "henitai/subject_resolver"
  autoload :GitDiffAnalyzer, "henitai/git_diff_analyzer"
  autoload :GitDiffError, "henitai/git_diff_analyzer"
  autoload :MutantGenerator, "henitai/mutant_generator"
  autoload :MutantHistoryStore, "henitai/mutant_history_store"
  autoload :AridNodeFilter, "henitai/arid_node_filter"
  autoload :AvailableCpuCount, "henitai/available_cpu_count"
  autoload :EquivalenceDetector, "henitai/equivalence_detector"
  autoload :StaticFilter, "henitai/static_filter"
  autoload :StillbornFilter, "henitai/stillborn_filter"
  autoload :ScenarioExecutionResult, "henitai/scenario_execution_result"
  autoload :CoverageFormatter, "henitai/coverage_formatter"
  autoload :MinitestCoverageReporter, "henitai/minitest_coverage_reporter"
  autoload :PerTestCoverageCollector, "henitai/per_test_coverage_collector"
  autoload :SyntaxValidator, "henitai/syntax_validator"
  autoload :SamplingStrategy, "henitai/sampling_strategy"
  autoload :TestPrioritizer, "henitai/test_prioritizer"
  autoload :ExecutionEngine, "henitai/execution_engine"
  autoload :Runner, "henitai/runner"
  autoload :Reporter, "henitai/reporter"
  autoload :Integration, "henitai/integration"
  autoload :Result, "henitai/result"
  autoload :WarningSilencer, "henitai/warning_silencer"
  autoload :CLI, "henitai/cli"
end
