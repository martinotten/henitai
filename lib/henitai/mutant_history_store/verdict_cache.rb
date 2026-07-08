# frozen_string_literal: true

require_relative "../verdict_fingerprint"

module Henitai
  class MutantHistoryStore
    # Verdict-cache column handling for the incremental (`--incremental`)
    # reuse feature. Mixed into {MutantHistoryStore}.
    module VerdictCache
      private

      # Hashes are persisted for killed mutants only — they are the reusable
      # verdicts; every other status stays NULL and always re-executes.
      # Cache-hit mutants (from_cache) were never executed this run, so their
      # covered tests are unknown — carry the stored fingerprints forward
      # instead of recomputing them from empty data (which would wipe them
      # and silently disable reuse after one cached run).
      def verdict_cache_bindings(mutant, existing_row)
        return [nil, nil] unless mutant.status.to_s == "killed"
        return existing_cache_bindings(existing_row) if from_cache?(mutant)

        [
          VerdictFingerprint.subject_source_hash(mutant),
          VerdictFingerprint.tests_fingerprint(covered_tests_for(mutant))
        ]
      end

      def existing_cache_bindings(existing_row)
        return [nil, nil] unless existing_row

        [existing_row["subject_source_hash"], existing_row["covered_tests_fingerprint"]]
      end

      def from_cache?(mutant)
        mutant.respond_to?(:from_cache?) && mutant.from_cache?
      end

      def covered_tests_for(mutant)
        mutant.respond_to?(:covered_by) ? mutant.covered_by : nil
      end
    end
  end
end
