# frozen_string_literal: true

module Henitai
  # The collaborators {Runner} drives, built on first use.
  #
  # Extracted so each one can be asserted on directly — several are chosen by
  # configuration (the integration adapter, the operator set, which progress
  # reporters are composed) and that choice had no test seam while it lived
  # behind private readers on `Runner`.
  #
  # Memoization is not an optimisation here, it is a correctness requirement for
  # {#per_test_coverage} and {#history_store}: the incremental filter proves
  # survivor reuse against the same live coverage map the history store records
  # its intersection set from. Two instances would be two snapshots.
  #
  # {#source_selection_coverage} is deliberately a *different* instance: Gate 1
  # reads the map as it was before this run's coverage bootstrap rewrote it, and
  # a shared instance would memoize that stale snapshot for the reuse decisions.
  class RunnerDependencies
    def initialize(config:)
      @config = config
    end

    def subject_resolver = @subject_resolver ||= SubjectResolver.new
    def git_diff_analyzer = @git_diff_analyzer ||= GitDiffAnalyzer.new
    def mutant_generator = @mutant_generator ||= MutantGenerator.new
    def static_filter = @static_filter ||= StaticFilter.new
    def execution_engine = @execution_engine ||= ExecutionEngine.new
    def coverage_bootstrapper = @coverage_bootstrapper ||= CoverageBootstrapper.new

    def integration
      @integration ||= Integration.for(@config.integration).new
    end

    def operators
      @operators ||= Operator.for_set(@config.operators)
    end

    def per_test_coverage
      @per_test_coverage ||= PerTestCoverage.new(reports_dir: @config.reports_dir)
    end

    def source_selection_coverage
      @source_selection_coverage ||= PerTestCoverage.new(reports_dir: @config.reports_dir)
    end

    def history_store
      @history_store ||= MutantHistoryStore.new(
        path: File.join(@config.reports_dir, Henitai::HISTORY_STORE_FILENAME),
        per_test_coverage: per_test_coverage,
        reuse_context: reuse_context
      )
    end

    # Shared by the incremental filter and the history store: verdicts are
    # recorded under exactly the context they are later checked against.
    def reuse_context
      @reuse_context ||= ReuseContext.new(config: @config)
    end

    # Fans progress out to the terminal reporter (when enabled) and the
    # checkpoint writer (when enabled and a file report is configured), so a
    # long run persists partial results incrementally.
    #
    # Deliberately *not* memoized: `full_run?` is a property of the invocation,
    # not of the dependency set, and a cached reporter would silently keep the
    # first answer.
    def progress_reporter(full_run:)
      CompositeProgressReporter.for(config: @config, source_provider: source_provider, full_run: full_run)
    end

    # Reads each source file once and caches it per path, so Result consumes
    # source content while performing no disk IO of its own. Unreadable files
    # (recipe stubs with synthetic locations, say) answer "" rather than
    # aborting the run.
    #
    # Not memoized: each call gets its own cache, scoped to one reporter's
    # lifetime rather than shared across the process.
    def source_provider
      cache = {} # : Hash[String, String]
      lambda do |file|
        cache[file] ||= begin
          File.read(file)
        rescue StandardError
          ""
        end
      end
    end
  end
end
