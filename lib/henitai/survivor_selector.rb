# frozen_string_literal: true

module Henitai
  # Filters a mutant list to those that match a set of prior survivor stable IDs.
  #
  # After calling #select, #unmatched_ids reports which survivor IDs had no
  # corresponding mutant in the current generation. A high unmatched ratio
  # indicates that the source has drifted and a full run is recommended.
  class SurvivorSelector
    DRIFT_THRESHOLD = 0.5

    def initialize(survivor_ids:)
      @survivor_ids  = survivor_ids.to_set
      @unmatched_ids = nil
    end

    def select(mutants)
      current_index = mutants.to_h { |m| [m.stable_id, m] }
      matched_ids, @unmatched_ids = @survivor_ids.partition { |id| current_index.key?(id) }
      matched_ids.filter_map { |id| current_index[id] }
    end

    def unmatched_ids
      raise "Call #select before accessing #unmatched_ids" if @unmatched_ids.nil?

      @unmatched_ids
    end

    def drift_warning?
      return false if @survivor_ids.empty?

      unmatched_ids.size.to_f / @survivor_ids.size > DRIFT_THRESHOLD
    end
  end
end
