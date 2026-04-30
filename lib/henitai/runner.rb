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
  # rubocop:disable Metrics/ClassLength
  class Runner
    attr_reader :config, :result

    def initialize(config: Configuration.load, subjects: nil, since: nil, survivors_from: nil)
      @config         = config
      @subjects       = subjects
      @since          = since
      @survivors_from = survivors_from
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

      mutants = if survivor_rerun? && (fast_mutants = try_recipe_run)
                  execute_mutants(fast_mutants)
                else
                  source_files = self.source_files
                  subjects = resolve_subjects(source_files)
                  execute_mutants(mutants_for(subjects, source_files))
                end

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
      bootstrap_thread = bootstrap_mutants(source_files)
      mutants = generate_mutants(subjects)
      bootstrap_thread.value
      filtered = filter_mutants(mutants)
      apply_survivor_selection(filtered)
    end

    def bootstrap_mutants(source_files)
      Thread.new { bootstrap_coverage(source_files) }
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
        thresholds: result_thresholds,
        partial_rerun: survivor_rerun?,
        survivor_stats: @survivor_stats,
        git_sha: safe_head_sha
      )
      persist_history(@result, finished_at)
      report(@result)
      @result
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

    def result_thresholds
      return nil unless config.respond_to?(:thresholds)

      config.thresholds
    end

    def survivor_rerun?
      !@survivors_from.nil?
    end

    def apply_survivor_selection(mutants)
      return mutants unless survivor_rerun?

      dirty_worktree_files = dirty_worktree_changed_files
      loaded   = SurvivorLoader.new(@survivors_from, include_paths: Array(config.includes)).load
      selector = SurvivorSelector.new(survivor_ids: loaded.survivor_ids)
      selected = selector.select(mutants)
      finalize_survivor_split(
        selector,
        selected,
        test_filter(
          loaded,
          dirty_source_files: dirty_source_files?(dirty_worktree_files, git_sha: loaded.git_sha)
        ).apply(selected)
      )
    end

    # Attempts to run survivors directly from pre-computed activation recipes,
    # bypassing source parsing and mutant generation entirely.
    # Returns the mutant array on success, or nil if recipes are unavailable.
    def try_recipe_run
      dirty_worktree_files = dirty_worktree_changed_files
      loaded       = SurvivorLoader.new(@survivors_from, include_paths: Array(config.includes)).load
      survivor_ids = loaded.survivor_ids
      recipes      = load_activation_recipes(survivor_ids)
      return nil if recipes.nil?

      selector, stubs = recipe_selector_and_stubs(survivor_ids, recipes)
      split = test_filter(
        loaded,
        dirty_source_files: dirty_source_files?(dirty_worktree_files, git_sha: loaded.git_sha)
      ).apply(stubs)
      finalize_survivor_split(selector, stubs, split)
    end

    # Builds stub Mutants from recipes and a SurvivorSelector primed with the
    # survivor ID set. The selector is given a synthetic #select call so that
    # #drift_warning? / #unmatched_ids are available (all IDs will be matched).
    def recipe_selector_and_stubs(survivor_ids, recipes)
      stubs    = survivor_ids.map { |id| build_stub_mutant(id, recipes[id]) }
      selector = SurvivorSelector.new(survivor_ids:)
      selector.select(stubs)
      [selector, stubs]
    end

    # Returns the recipe hash if the file exists and covers every survivor ID;
    # otherwise returns nil to trigger the normal generation path.
    def load_activation_recipes(survivor_ids)
      path    = File.join(File.dirname(@survivors_from), SurvivorActivationCache::FILENAME)
      recipes = SurvivorActivationCache.load(path)
      return nil if recipes.nil?
      return nil unless survivor_ids.all? { |id| recipes.key?(id) }

      recipes
    end

    def build_stub_mutant(stable_id, recipe)
      mutant = Mutant.new(
        subject: stub_subject_from_recipe(recipe),
        operator: recipe.fetch("operator"),
        nodes: { original: nil, mutated: nil },
        description: recipe.fetch("description"),
        location: recipe_location(recipe["location"]),
        precomputed_stable_id: stable_id,
        precomputed_activation_source: recipe.fetch("activationSource")
      )
      mutant.covered_by = recipe["coveredBy"]
      mutant
    end

    def stub_subject_from_recipe(recipe)
      Subject.new(
        namespace: recipe["namespace"],
        method_name: recipe["methodName"],
        method_type: (recipe["methodType"] || "instance").to_sym,
        source_location: { file: recipe["sourceFile"], range: nil }
      )
    end

    def recipe_location(loc)
      return {} unless loc.is_a?(Hash)

      {
        file: loc["file"],
        start_line: loc["startLine"],
        end_line: loc["endLine"],
        start_col: loc["startCol"],
        end_col: loc["endCol"]
      }.compact
    end

    def finalize_survivor_split(selector, selected, split)
      split[:stable].each { |m| m.status = :survived }
      warn_survivor_drift(selector) if selector.drift_warning?
      @survivor_stats = build_survivor_stats(selector, selected, split)
      split[:stable] + split[:pending]
    end

    def test_filter(loaded, dirty_source_files: false)
      SurvivorTestFilter.new(
        coverage_map: loaded.coverage_map,
        git_sha: loaded.git_sha,
        dirty_source_files:,
        worktree_changed_files: Array(dirty_worktree_changed_files),
        diff_analyzer: git_diff_analyzer
      )
    end

    def dirty_worktree_changed_files
      @dirty_worktree_changed_files ||= git_diff_analyzer.working_tree_changed_files
    rescue StandardError
      nil
    end

    def dirty_source_files?(dirty_worktree_files, git_sha: nil)
      return true if dirty_worktree_files.nil?

      all_changed = dirty_worktree_files + committed_changed_files(git_sha)
      include_roots = Array(config.includes).map { |path| normalize_path(path) }
      all_changed.any? { |path| in_include_root?(normalize_path(path), include_roots) }
    rescue StandardError
      true
    end

    def committed_changed_files(git_sha)
      return [] unless git_sha

      git_diff_analyzer.changed_files(from: git_sha, to: "HEAD")
    end

    def in_include_root?(path, include_roots)
      include_roots.any? { |root| path == root || path.start_with?("#{root}/") }
    end

    def warn_survivor_drift(selector)
      warn "henitai: WARNING: #{selector.unmatched_ids.size} prior survivors " \
           "could not be matched; the source may have drifted - consider a full run"
    end

    def build_survivor_stats(selector, selected, split)
      {
        matched: selected.size,
        unmatched_count: selector.unmatched_ids.size,
        unmatched_ids: selector.unmatched_ids,
        skipped_count: split[:stable].size,
        drift_warning: selector.drift_warning?
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
