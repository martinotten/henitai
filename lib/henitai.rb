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

  # Raised when another process is using the configured reports directory.
  class ConcurrentRunError < StandardError; end

  autoload :Configuration, "henitai/configuration"
  autoload :CoverageBootstrapper, "henitai/coverage_bootstrapper"
  autoload :CoverageReportReader, "henitai/coverage_report_reader"
  autoload :PerTestCoverage, "henitai/per_test_coverage"
  autoload :PerTestCoverageSelector, "henitai/per_test_coverage_selector"
  autoload :Subject, "henitai/subject"
  autoload :Mutant, "henitai/mutant"
  autoload :MutantIdentity, "henitai/mutant_identity"
  autoload :Operator, "henitai/operator"
  autoload :Operators, "henitai/operators"
  autoload :SourceParser, "henitai/source_parser"
  autoload :SubjectResolver, "henitai/subject_resolver"
  autoload :GeneratedArtifacts, "henitai/generated_artifacts"
  autoload :GitDiffAnalyzer, "henitai/git_diff_analyzer"
  autoload :GitDiffError, "henitai/git_diff_analyzer"
  autoload :MutantGenerator, "henitai/mutant_generator"
  autoload :MutantHistoryStore, "henitai/mutant_history_store"
  autoload :MutationSkipDirectives, "henitai/mutation_skip_directives"
  autoload :AridNodeFilter, "henitai/arid_node_filter"
  autoload :AvailableCpuCount, "henitai/available_cpu_count"
  autoload :EquivalenceDetector, "henitai/equivalence_detector"
  autoload :StaticFilter, "henitai/static_filter"
  autoload :IncrementalFilter, "henitai/incremental_filter"
  autoload :VerdictFingerprint, "henitai/verdict_fingerprint"
  autoload :StillbornFilter, "henitai/stillborn_filter"
  autoload :CanonicalReportMerger, "henitai/canonical_report_merger"
  autoload :CanonicalReportWriter, "henitai/canonical_report_writer"
  autoload :CheckpointReporter, "henitai/checkpoint_reporter"
  autoload :CompositeProgressReporter, "henitai/composite_progress_reporter"
  autoload :ReportsDirectoryLock, "henitai/reports_directory_lock"
  autoload :SurvivorLoader,          "henitai/survivor_loader"
  autoload :SurvivorSelector,        "henitai/survivor_selector"
  autoload :SurvivorTestFilter,      "henitai/survivor_test_filter"
  autoload :SurvivorActivationCache, "henitai/survivor_activation_cache"
  autoload :SurvivorRerunStrategy, "henitai/survivor_rerun_strategy"
  autoload :ScenarioExecutionResult, "henitai/scenario_execution_result"
  autoload :CoverageFormatter, "henitai/coverage_formatter"
  autoload :MinitestCoverageReporter, "henitai/minitest_coverage_reporter"
  autoload :PerTestCoverageCollector, "henitai/per_test_coverage_collector"
  autoload :SyntaxValidator, "henitai/syntax_validator"
  autoload :SamplingStrategy, "henitai/sampling_strategy"
  autoload :TestPrioritizer, "henitai/test_prioritizer"
  autoload :ExcludedTestFilter, "henitai/excluded_test_filter"
  autoload :TimeoutCalibrator, "henitai/timeout_calibrator"
  autoload :ExecutionEngine, "henitai/execution_engine"
  autoload :ProcessWorkerRunner, "henitai/process_worker_runner"
  autoload :SlotScheduler, "henitai/slot_scheduler"
  autoload :ProcessWakeup, "henitai/process_wakeup"
  autoload :ProcessLiveness, "henitai/process_liveness"
  autoload :InheritedFdRegistry, "henitai/inherited_fd_registry"
  autoload :OrphanWatchdog, "henitai/orphan_watchdog"
  autoload :Runner, "henitai/runner"
  autoload :Reporter, "henitai/reporter"
  autoload :Integration, "henitai/integration"
  autoload :Result, "henitai/result"
  autoload :WarningSilencer, "henitai/warning_silencer"
  autoload :CLI, "henitai/cli"
end
