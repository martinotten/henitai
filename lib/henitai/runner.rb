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
    # @return [Result]
    def run
      started_at = Time.now
      source_files = self.source_files
      bootstrap_coverage(source_files)
      subjects = resolve_subjects(source_files)
      mutants = generate_mutants(subjects)
      mutants = filter_mutants(mutants)
      mutants = execute_mutants(mutants)
      finished_at = Time.now

      build_result(mutants, started_at, finished_at)
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
        finished_at:
      )
      persist_history(@result, finished_at)
      report(@result)
      @result
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

    def bootstrap_coverage(source_files)
      coverage_bootstrapper.ensure!(
        source_files:,
        config:,
        integration:
      )
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

    def unique_subjects(subjects)
      subjects.uniq { |subject| [subject.expression, subject.source_file] }
    end

    def normalize_path(path)
      File.expand_path(path)
    end
  end
end
