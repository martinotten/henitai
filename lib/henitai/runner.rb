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

    def initialize(config: Configuration.load, subjects: nil, since: nil)
      @config   = config
      @subjects = subjects
      @since    = since
    end

    # Entry point — runs the full pipeline and returns a Result.
    #
    # Coverage bootstrap (Gate 0) runs in a background thread so that Gate 1
    # (subject resolution) and Gate 2 (mutant generation) proceed concurrently.
    # The thread is joined before Gate 3 (static filtering), which is the first
    # phase that requires coverage data.
    #
    # For targeted runs (`subjects:` provided), the bootstrap is further scoped
    # to the spec files that cover the requested subjects rather than the full
    # suite, reducing the baseline run time proportionally.
    #
    # @return [Result]
    def run
      started_at = Time.now
      source_files = self.source_files
      subjects = resolve_subjects(source_files)
      mutants = execute_mutants(mutants_for(subjects, source_files))

      build_result(mutants, started_at, Time.now)
    end

    private

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
      bootstrap_thread = bootstrap_mutants(source_files, subjects)
      mutants = generate_mutants(subjects)
      bootstrap_thread.value

      filtered_mutants = filter_mutants(mutants)
      return filtered_mutants unless targeted_run?

      refresh_coverage_for_targeted_run(filtered_mutants, source_files)
    end

    def refresh_coverage_for_targeted_run(mutants, source_files)
      return mutants unless retry_full_bootstrap?(mutants)

      bootstrap_coverage(source_files)
      filter_mutants(mutants)
    end

    def bootstrap_mutants(source_files, subjects)
      scoped_tests = scoped_bootstrap_test_files(subjects)
      Thread.new { bootstrap_coverage(source_files, scoped_tests) }
    end

    def execute_mutants(mutants)
      execution_engine.run(
        mutants,
        integration,
        config,
        progress_reporter: progress_reporter
      )
    end

    def report(result)
      Reporter.run_all(names: config.reporters, result:, config:)
    end

    def persist_history(result, recorded_at)
      history_store.record(
        result,
        version: Henitai::VERSION,
        recorded_at:
      )
    end

    def build_result(mutants, started_at, finished_at)
      @result = Result.new(
        mutants:,
        started_at:,
        finished_at:,
        thresholds: result_thresholds
      )
      persist_history(@result, finished_at)
      report(@result)
      @result
    end

    # Returns the spec files to use for the coverage bootstrap.
    #
    # For full runs (no subject pattern given), returns nil so the bootstrapper
    # falls back to the integration's full test-file list.
    #
    # For targeted runs, returns the union of test files selected for each
    # resolved subject. Falls back to nil (all tests) if the selection is empty,
    # so the bootstrapper always has a non-empty file list.
    def scoped_bootstrap_test_files(subjects)
      return nil if pattern_subjects.empty?

      files = subjects.flat_map { |subject| integration.select_tests(subject) }.uniq
      files.empty? ? nil : files
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

    def progress_reporter
      return nil unless Array(config.reporters).map(&:to_s).include?("terminal")

      Reporter::Terminal.new(config:)
    end

    def history_store
      @history_store ||= MutantHistoryStore.new(
        path: File.join(config.reports_dir, Henitai::HISTORY_STORE_FILENAME)
      )
    end

    def source_files
      @source_files ||= begin
        included_files = Array(config.includes).flat_map do |include_path|
          Dir.glob(File.join(include_path, "**", "*.rb"))
        end.uniq

        if @since
          changed_files = git_diff_analyzer.changed_files(from: @since, to: "HEAD")
          changed_file_set = changed_files.map { |path| normalize_path(path) }

          included_files.select do |path|
            changed_file_set.include?(normalize_path(path))
          end
        else
          included_files
        end
      end
    end

    def pattern_subjects
      Array(@subjects)
    end

    def targeted_run?
      !pattern_subjects.empty?
    end

    def retry_full_bootstrap?(mutants)
      executable_mutants = Array(mutants).reject do |mutant|
        %i[ignored compile_error equivalent].include?(mutant.status)
      end
      return false if executable_mutants.empty?

      executable_mutants.all? { |mutant| mutant.status == :no_coverage }
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
  end
end
