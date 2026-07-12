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
    def initialize(config: Configuration.load, subjects: nil, since: nil, survivors_from: nil,
                   mode: {})
      @config         = config
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
      started_at = Time.now

      mutants = pipeline_mutants
      return dry_run_result(mutants, started_at, Time.now) if @dry_run

      build_result(execute_mutants(mutants), started_at, Time.now)
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
    # a Result without executing tests, persisting history or running the
    # configured reporters — reports/ stays untouched.
    def dry_run_result(mutants, started_at, finished_at)
      @result = build_result_object(mutants, started_at, finished_at)
      Reporter::DryRun.new(config:).report(@result)
      @result
    end

    def resolve_subjects(source_files = self.source_files)
      subjects = subject_resolver.resolve_from_files(source_files)
      return subjects if pattern_subjects.empty?

      selected_subjects = pattern_subjects.flat_map do |pattern|
        subject_resolver.apply_pattern(subjects, pattern.expression)
      end
      unique_subjects(selected_subjects)
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
        partial_rerun: survivor_rerun?,
        survivor_stats: survivor_strategy.survivor_stats,
        git_sha: safe_head_sha,
        source_provider: source_provider,
        authoritative: full_run?
      )
    end

    # Reads each source file once and caches it, so Result consumes source
    # content while performing no disk IO of its own. Returns "" for files that
    # cannot be read (e.g. recipe stubs with synthetic locations).
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

    def subject_resolver
      @subject_resolver ||= SubjectResolver.new
    end

    def git_diff_analyzer
      @git_diff_analyzer ||= GitDiffAnalyzer.new
    end

    def mutant_generator
      @mutant_generator ||= MutantGenerator.new
    end

    def static_filter
      @static_filter ||= StaticFilter.new
    end

    def execution_engine
      @execution_engine ||= ExecutionEngine.new
    end

    def coverage_bootstrapper
      @coverage_bootstrapper ||= CoverageBootstrapper.new
    end

    def integration
      @integration ||= Integration.for(config.integration).new
    end

    def operators
      @operators ||= Operator.for_set(config.operators)
    end

    # Fans progress out to the terminal reporter (when enabled) and the
    # checkpoint writer (when enabled and a file report is configured), so a
    # long run persists partial results incrementally.
    def progress_reporter
      CompositeProgressReporter.for(config:, source_provider:, full_run: full_run?)
    end

    def history_store
      @history_store ||= MutantHistoryStore.new(
        path: File.join(config.reports_dir, Henitai::HISTORY_STORE_FILENAME), per_test_coverage:
      )
    end

    # One shared live view of the per-test coverage map: the incremental
    # filter proves survivor reuse against it and the history store records
    # the same intersection set — one implementation, one snapshot.
    def per_test_coverage
      @per_test_coverage ||= PerTestCoverage.new(reports_dir: config.reports_dir)
    end

    def source_files
      @source_files ||= filter_changed(reject_excluded(included_source_files))
    end

    def included_source_files
      Array(config.includes).flat_map do |include_path|
        Dir.glob(File.join(include_path, "**", "*.rb"))
      end.uniq
    end

    # Drops files matched by any `excludes:` glob (e.g. standalone entry points
    # that cannot be mutation-tested in-process). Excludes apply regardless of
    # the --since filter.
    def reject_excluded(files)
      excluded = excluded_source_files
      return files if excluded.empty?

      files.reject { |path| excluded.include?(normalize_path(path)) }
    end

    def excluded_source_files
      Array(config.excludes)
        .flat_map { |pattern| Dir.glob(pattern) }
        .map { |path| normalize_path(path) }
    end

    def filter_changed(files)
      return files unless @since

      changed_file_set = git_diff_analyzer
                         .changed_files(from: @since, to: "HEAD")
                         .map { |path| normalize_path(path) }
      files.select { |path| changed_file_set.include?(normalize_path(path)) }
    end

    def pattern_subjects
      Array(@subjects)
    end

    def unique_subjects(subjects)
      subjects.uniq { |subject| [subject.expression, subject.source_file] }
    end

    def normalize_path(path)
      File.expand_path(path)
    end

    def result_thresholds
      return nil unless config.respond_to?(:thresholds)

      config.thresholds
    end

    def survivor_rerun?
      !@survivors_from.nil?
    end

    # Mutation-scope full run, controlling Result#authoritative? — distinct
    # from the per-test-coverage plan's test-suite-scope "full run".
    def full_run?
      pattern_subjects.empty? && @since.nil? && !survivor_rerun?
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
