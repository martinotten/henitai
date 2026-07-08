# frozen_string_literal: true

require_relative "verdict_fingerprint"

module Henitai
  # Marks mutants whose Killed verdict from a prior run is still valid so
  # `--incremental` runs skip re-executing them (Gate 3.5, opt-in).
  #
  # Reuse rule (conservative): the stored verdict must be Killed, carry both
  # fingerprints, and both the subject's source and every recorded covering
  # test file must be byte-identical to what was recorded. Survivors,
  # timeouts, errors, unknown ids and legacy rows always re-execute.
  class IncrementalFilter
    def initialize(history_store:)
      @history_store = history_store
    end

    # @return [Array<Mutant>] the same collection; cache hits get status
    #   :killed and from_cache = true.
    def apply(mutants)
      collection = Array(mutants)
      ambiguous = ambiguous_stable_ids(collection)
      collection.each do |mutant|
        next unless mutant.pending?
        next if ambiguous.include?(mutant.stable_id)
        next unless reusable?(mutant)

        mutant.status = :killed
        mutant.from_cache = true if mutant.respond_to?(:from_cache=)
      end

      mutants
    end

    private

    attr_reader :history_store

    # MutantIdentity deliberately omits source coordinates (line-drift
    # tolerance), so distinct mutants inside one subject can share a stable
    # id. A shared id makes the stored verdict ambiguous — one colliding
    # mutant may have been killed while another errored — so reuse is skipped
    # for every mutant whose id appears more than once in this run.
    def ambiguous_stable_ids(mutants)
      mutants.group_by(&:stable_id).filter_map do |stable_id, group|
        stable_id if group.size > 1
      end.to_set
    end

    def reusable?(mutant)
      verdict = history_store.killed_verdict_for(mutant.stable_id)
      return false unless verdict

      VerdictFingerprint.subject_source_hash(mutant) == verdict.fetch(:subject_source_hash) &&
        VerdictFingerprint.tests_fingerprint_current?(verdict.fetch(:covered_tests_fingerprint))
    end
  end
end
