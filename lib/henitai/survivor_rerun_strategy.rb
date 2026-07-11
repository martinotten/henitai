# frozen_string_literal: true

module Henitai
  # Survivor-rerun fast path for {Runner}.
  #
  # When +--survivors-from+ is given, this collaborator loads the prior report
  # and either:
  #
  #   * builds stub Mutants directly from +activation-recipes.json+ (the recipe
  #     fast path, bypassing source parsing and mutant generation), or
  #   * filters a freshly generated mutant list down to the prior survivors.
  #
  # In both cases it records {#survivor_stats} (matched/unmatched counts and the
  # drift warning) for the Runner to attach to its Result.
  class SurvivorRerunStrategy
    attr_reader :survivor_stats

    def initialize(survivors_from:, config:, git_diff_analyzer:)
      @survivors_from = survivors_from
      @config = config
      @git_diff_analyzer = git_diff_analyzer
      @survivor_stats = nil
    end

    def active?
      !@survivors_from.nil?
    end

    # Attempts to run survivors directly from pre-computed activation recipes,
    # bypassing source parsing and mutant generation entirely.
    # Returns the mutant array on success, or nil if recipes are unavailable.
    def try_recipe_run
      dirty_worktree_files = dirty_worktree_changed_files
      loaded = load_survivor_report
      return nil unless recipe_fast_path_safe?(loaded, dirty_worktree_files)

      run_from_recipes(loaded, dirty_worktree_files)
    end

    def apply_selection(mutants)
      dirty_worktree_files = dirty_worktree_changed_files
      loaded   = load_survivor_report
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

    private

    def load_survivor_report
      SurvivorLoader.new(@survivors_from, include_paths: Array(@config.includes)).load
    end

    def run_from_recipes(loaded, dirty_worktree_files)
      recipes = load_activation_recipes(loaded.survivor_ids)
      return nil if recipes.nil?

      selector, stubs = recipe_selector_and_stubs(loaded.survivor_ids, recipes)
      split = test_filter(
        loaded,
        dirty_source_files: dirty_source_files?(dirty_worktree_files, git_sha: loaded.git_sha)
      ).apply(stubs)
      finalize_survivor_split(selector, stubs, split)
    end

    def recipe_fast_path_safe?(loaded, dirty_worktree_files)
      !dirty_source_files?(dirty_worktree_files, git_sha: loaded.git_sha)
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

    def test_filter(loaded, dirty_source_files:)
      SurvivorTestFilter.new(
        coverage_map: loaded.coverage_map,
        git_sha: loaded.git_sha,
        dirty_source_files:,
        worktree_changed_files: Array(dirty_worktree_changed_files),
        diff_analyzer: @git_diff_analyzer
      )
    end

    def dirty_worktree_changed_files
      @dirty_worktree_changed_files ||= @git_diff_analyzer.working_tree_changed_files
    rescue StandardError
      nil
    end

    def dirty_source_files?(dirty_worktree_files, git_sha: nil)
      return true if dirty_worktree_files.nil?

      all_changed = dirty_worktree_files + committed_changed_files(git_sha)
      include_roots = Array(@config.includes).map { |path| normalize_path(path) }
      all_changed.any? { |path| in_include_root?(normalize_path(path), include_roots) }
    rescue StandardError
      true
    end

    def committed_changed_files(git_sha)
      return [] unless git_sha

      @git_diff_analyzer.changed_files(from: git_sha, to: "HEAD")
    end

    def in_include_root?(path, include_roots)
      include_roots.any? { |root| path == root || path.start_with?("#{root}/") }
    end

    def normalize_path(path)
      File.expand_path(path)
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
end
