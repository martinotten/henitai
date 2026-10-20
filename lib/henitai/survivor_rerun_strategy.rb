# frozen_string_literal: true

require_relative "dirty_source_detector"

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
  # Survivors are never trusted on the strength of the prior report alone: a
  # selected survivor is skipped only when the {IncrementalFilter} content
  # fingerprint rules prove its stored verdict still valid (new or edited
  # tests, helpers and configuration all force a re-run). Recipe stubs have no
  # source range to fingerprint, so they always re-run.
  #
  # In both cases it records {#survivor_stats} (matched/unmatched counts, the
  # reused-verdict count and the drift warning) for the Runner to attach to
  # its Result.
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
      loaded = load_survivor_report
      return nil unless recipe_fast_path_safe?(loaded)

      run_from_recipes(loaded)
    end

    # @param reuse_filter [IncrementalFilter, nil] marks survivors whose
    #   stored verdict is provably still valid as cache hits.
    def apply_selection(mutants, reuse_filter: nil)
      selector = SurvivorSelector.new(survivor_ids: load_survivor_report.survivor_ids)
      selected = selector.select(mutants)
      reuse_filter&.apply(selected)
      finalize_selection(selector, selected)
    end

    private

    def load_survivor_report
      SurvivorLoader.new(@survivors_from, include_paths: Array(@config.includes)).load
    end

    def run_from_recipes(loaded)
      recipes = load_activation_recipes(loaded.survivor_ids)
      return nil if recipes.nil?

      selector, stubs = recipe_selector_and_stubs(loaded.survivor_ids, recipes)
      finalize_selection(selector, stubs)
    end

    def recipe_fast_path_safe?(loaded)
      !dirty_source_files?(dirty_worktree_changed_files, git_sha: loaded.git_sha)
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
      return nil unless survivor_ids.all? { |id| replayable_recipe?(recipes[id]) }

      recipes
    end

    # Recipes without an "activation" entry predate ADR-13: their
    # define_method sources lose lexical scope, so they are not replayed.
    # A :toplevel activation needs the persisted scope and owner, because the
    # stub subject has no AST to resolve them from.
    def replayable_recipe?(recipe)
      return false unless recipe.is_a?(Hash) && recipe["activation"].is_a?(Hash)

      activation = recipe["activation"]
      activation["mode"] != "toplevel" || toplevel_fields_valid?(activation)
    end

    def toplevel_fields_valid?(activation)
      scope = activation["lexicalScope"]
      scope.is_a?(Array) && scope.all?(String) &&
        activation["owner"].is_a?(String) &&
        [true, false].include?(activation["singleton"])
    end

    def build_stub_mutant(stable_id, recipe)
      mutant = Mutant.new(
        subject: stub_subject_from_recipe(recipe),
        operator: recipe.fetch("operator"),
        nodes: { original: nil, mutated: nil },
        description: recipe.fetch("description"),
        location: recipe_location(recipe["location"]),
        precomputed_stable_id: stable_id,
        precomputed_activation: Mutant::Activation.from_h(recipe.fetch("activation")),
        precomputed_replacement: recipe["replacement"]
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

    def finalize_selection(selector, selected)
      warn_survivor_drift(selector) if selector.drift_warning?
      @survivor_stats = build_survivor_stats(selector, selected)
      selected
    end

    def dirty_worktree_changed_files
      @dirty_worktree_changed_files ||= @git_diff_analyzer.working_tree_changed_files
    rescue StandardError
      nil
    end

    def dirty_source_files?(dirty_worktree_files, git_sha: nil)
      dirty_source_detector.dirty?(dirty_worktree_files, git_sha: git_sha)
    end

    def dirty_source_detector
      @dirty_source_detector ||= DirtySourceDetector.new(
        includes: @config.includes, git_diff_analyzer: @git_diff_analyzer
      )
    end

    def warn_survivor_drift(selector)
      warn "henitai: WARNING: #{selector.unmatched_ids.size} prior survivors " \
           "could not be matched; the source may have drifted - consider a full run"
    end

    def build_survivor_stats(selector, selected)
      {
        matched: selected.size,
        unmatched_count: selector.unmatched_ids.size,
        unmatched_ids: selector.unmatched_ids,
        skipped_count: selected.count(&:from_cache?),
        drift_warning: selector.drift_warning?
      }
    end
  end
end
