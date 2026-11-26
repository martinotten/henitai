# frozen_string_literal: true

module Henitai
  # Selects current mutants by the survivor IDs in a prior report and
  # records matching and verdict reuse statistics for the runner.
  class SurvivorRerunStrategy
    attr_reader :survivor_stats

    def initialize(survivors_from:, config:)
      @survivors_from = survivors_from
      @config = config
      @survivor_stats = nil
    end

    def active?
      !@survivors_from.nil?
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

    def finalize_selection(selector, selected)
      warn_survivor_drift(selector) if selector.drift_warning?
      @survivor_stats = build_survivor_stats(selector, selected)
      selected
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
