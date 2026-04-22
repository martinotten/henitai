# frozen_string_literal: true

require "set"

module Henitai
  # Splits a matched survivor set into stable and pending subsets by consulting
  # a git diff against the covering tests from the prior report.
  #
  # A survivor is **stable** (can skip re-execution) when:
  #   - it has covering test data in the prior report, AND
  #   - none of those test files appear in the diff between the prior run's
  #     git_sha and the current HEAD.
  #
  # A survivor is **pending** (must execute) when:
  #   - git_sha is nil (no anchor → conservative), OR
  #   - its coveredBy data is absent or empty, OR
  #   - at least one covering test file changed.
  #
  # On any git error the filter conservatively treats all survivors as pending.
  class SurvivorTestFilter
    # @param coverage_map  [Hash<String, Array<String>>] stableId → [test_files]
    # @param git_sha       [String, nil] git SHA from the prior report
    # @param diff_analyzer [GitDiffAnalyzer]
    def initialize(coverage_map:, git_sha:, diff_analyzer: GitDiffAnalyzer.new)
      @coverage_map  = coverage_map
      @git_sha       = git_sha
      @diff_analyzer = diff_analyzer
    end

    # @param mutants [Array<Mutant>]
    # @return [Hash<Symbol, Array<Mutant>>] { stable: [...], pending: [...] }
    def apply(mutants)
      return { stable: [], pending: mutants } if @git_sha.nil?

      changed = changed_test_files
      return { stable: [], pending: mutants } if changed.nil?

      mutants.each_with_object({ stable: [], pending: [] }) do |mutant, result|
        bucket = stable_survivor?(mutant, changed) ? :stable : :pending
        result[bucket] << mutant
      end
    end

    private

    def stable_survivor?(mutant, changed)
      covering = @coverage_map[mutant.stable_id]
      return false if covering.nil? || covering.empty?

      covering.none? { |test_file| changed.include?(test_file) }
    end

    # Returns a Set of changed test file paths, or nil on any git error
    # (nil triggers conservative fallback in #apply — all survivors pending).
    def changed_test_files
      @diff_analyzer.changed_files(from: @git_sha, to: "HEAD").to_set
    rescue StandardError
      nil
    end
  end
end
