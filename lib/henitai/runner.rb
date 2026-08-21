# frozen_string_literal: true

module Henitai
  # Orchestrates the full mutation testing pipeline.
  #
  # Pipeline phases (Phase-Gate model):
  #
  #   Gate 1 — Subject selection
  #     Resolve source files from includes, apply --since filter (incremental),
  #     build Subject list from AST.
  #
  #   Gate 2 — Mutant generation
  #     Apply operators to each Subject's AST. Filter arid (non-productive)
  #     nodes via ignore_patterns. Produces the initial mutant list.
  #
  #   Gate 3 — Static filtering
  #     Remove ignored mutants (pattern matches), compile-time errors.
  #     Apply per-test coverage data: mark :no_coverage for uncovered mutants.
  #
  #   Gate 4 — Mutant execution
  #     Run surviving mutants in isolated child processes (fork isolation).
  #     Each child process loads the test suite with the mutated method
  #     injected via Module#define_method. Collect kill/survive/timeout results.
  #
  #   Gate 5 — Reporting
  #     Write results to configured reporters (terminal, html, json, dashboard).
  #
  class Runner
    attr_reader :config, :result

    # @param mode [Hash] execution-mode flags: +dry_run:+ stops before Gate 4,
    #   +incremental:+ reuses still-valid Killed verdicts from history.
    # +deps+ is assigned in the body, not defaulted in the signature: the
    # default needs @config, and `config:` itself defaults to a load.
    #
    # rubocop:disable Metrics/ParameterLists -- these are the CLI's own flags
    # plus the dependency seam; a params object would only move the list.
    def initialize(config: Configuration.load, subjects: nil, since: nil, survivors_from: nil,
                   mode: {}, deps: nil)
      # rubocop:enable Metrics/ParameterLists
      @config         = config
      @deps           = deps || RunnerDependencies.new(config: @config)
      @subjects       = subjects
      @since          = since
      @survivors_from = survivors_from
      @dry_run        = mode.fetch(:dry_run, false)
      @incremental    = mode.fetch(:incremental, false)
    end

    # Entry point — runs the full pipeline and returns a Result.
    #
    # Fast path (recipe rerun): when +--survivors-from+ is given and an
    # +activation-recipes.json+ file exists beside the report with entries for
    # all survivor IDs, stub Mutants are built from the recipes and the full
    # source-parse / mutant-generation pipeline is skipped entirely.
    #
    # Normal path: Coverage bootstrap (Gate 0) runs in a background thread so
    # that Gate 1 (subject resolution) and Gate 2 (mutant generation) proceed
    # concurrently. The thread is joined before Gate 3 (static filtering).
    #
    # @return [Result]
    def run
      ReportsDirectoryLock.new(reports_dir: config.reports_dir).synchronize do
        started_at = Time.now

        mutants = pipeline_mutants
        return dry_run_result(mutants, started_at, Time.now) if @dry_run

        build_result(execute_mutants(mutants), started_at, Time.now)
      end
    end

    private

    # Gates 0–3 only: coverage bootstrap, subject resolution, generation and
    # static/skip/arid/stillborn filtering — everything short of execution.
    def pipeline_mutants
      if survivor_rerun? && (fast_mutants = survivor_strategy.try_recipe_run)
        return fast_mutants
      end

      source_files = self.source_files
      subjects = resolve_subjects(source_files)
      mutants_for(subjects, source_files)
    end

    # Dry run stops before Gate 4: prints the post-filter listing and returns
    # a Result without executing mutants, persisting history or running the
    # configured reporters. Gate 0 and lock coordination may still write under
    # reports_dir.
    def dry_run_result(mutants, started_at, finished_at)
      @result = build_result_object(mutants, started_at, finished_at)
      Reporter::DryRun.new(config:).report(@result)
      @result
    end

    def resolve_subjects(source_files = self.source_files)
      subject_selection.resolve(source_files)
    end

    def subject_selection
      @subject_selection ||= SubjectSelection.new(
        subject_resolver: subject_resolver, patterns: @subjects
      )
    end

    def generate_mutants(subjects)
      mutant_generator.generate(subjects, operators, config:)
    end

    def filter_mutants(mutants)
      static_filter.apply(mutants, config)
    end

    def mutants_for(subjects, source_files)
      bootstrap_thread = bootstrap_mutants(source_files)
      mutants = generate_mutants(subjects)
      bootstrap_thread.value
      filtered = apply_incremental_filter(filter_mutants(mutants))
      return filtered unless survivor_rerun?

      survivor_strategy.apply_selection(filtered)
    end

    # Opt-in verdict reuse (`--incremental`): still-valid Killed and Survived
    # verdicts from the history store are marked with their stored status +
    # from_cache before execution. The filter is only ever constructed when
    # the flag is set; it runs after the coverage bootstrap join in
    # mutants_for, so the live per-test map it reads is never mid-write.
    def apply_incremental_filter(mutants)
      return mutants unless @incremental

      IncrementalFilter.new(history_store:, per_test_coverage:,
                            dependency_fingerprint: VerdictFingerprint.dependency_fingerprint)
                       .apply(mutants)
    end

    def bootstrap_mutants(source_files) = Thread.new { bootstrap_coverage(source_files) }

    def execute_mutants(mutants)
      execution_engine.run(
        mutants,
        integration,
        config,
        progress_reporter: progress_reporter
      )
    end

    def report(result)
      Reporter.run_all(names: config.reporters, result:, config:, history_store:)
    end

    def persist_history(result, recorded_at)
      history_store.record(
        result,
        version: Henitai::VERSION,
        recorded_at:
      )
    end

    def build_result(mutants, started_at, finished_at)
      @result = build_result_object(mutants, started_at, finished_at)
      persist_history(@result, finished_at)
      report(@result)
      @result
    end

    def build_result_object(mutants, started_at, finished_at)
      Result.new(
        mutants:,
        started_at:,
        finished_at:,
        thresholds: result_thresholds,
        coverage_criteria: result_coverage_criteria,
        partial_rerun: survivor_rerun?,
        survivor_stats: survivor_strategy.survivor_stats,
        git_sha: safe_head_sha,
        source_provider: source_provider,
        authoritative: full_run?,
        since: @since
      )
    end

    def safe_head_sha
      git_diff_analyzer.head_sha
    rescue StandardError
      # `head_sha` rescues Errno::ENOENT. This extra rescue is defensive for
      # unexpected Open3/git runtime errors; conservative fallback is `nil`.
      nil
    end

    def bootstrap_coverage(source_files, test_files = nil)
      coverage_bootstrapper.ensure!(source_files:, config:, integration:, test_files:)
    end

    attr_reader :deps

    def subject_resolver = deps.subject_resolver
    def git_diff_analyzer = deps.git_diff_analyzer
    def mutant_generator = deps.mutant_generator
    def static_filter = deps.static_filter
    def execution_engine = deps.execution_engine
    def coverage_bootstrapper = deps.coverage_bootstrapper
    def integration = deps.integration
    def operators = deps.operators
    def history_store = deps.history_store
    def per_test_coverage = deps.per_test_coverage
    def source_provider = deps.source_provider

    def progress_reporter = deps.progress_reporter(full_run: full_run?)

    def source_files
      @source_files ||= source_file_selection.call
    end

    def source_file_selection
      @source_file_selection ||= SourceFileSelection.new(
        config: config, since: @since,
        git_diff_analyzer: git_diff_analyzer, per_test_coverage: per_test_coverage
      )
    end

    def result_thresholds = optional_config(:thresholds)

    def result_coverage_criteria = optional_config(:coverage_criteria)

    # Specs pass bare config doubles that expose only what the example needs, so
    # scoring inputs are read defensively rather than assumed present.
    def optional_config(name) = config.respond_to?(name) ? config.public_send(name) : nil

    def survivor_rerun? = !@survivors_from.nil?

    # Mutation-scope full run, controlling Result#authoritative? — distinct
    # from the per-test-coverage plan's test-suite-scope "full run".
    def full_run?
      Array(@subjects).empty? && @since.nil? && !survivor_rerun?
    end

    def survivor_strategy
      @survivor_strategy ||= SurvivorRerunStrategy.new(
        survivors_from: @survivors_from,
        config:,
        git_diff_analyzer:
      )
    end
  end
end
