# frozen_string_literal: true

require_relative "../verdict_fingerprint"

module Henitai
  class MutantHistoryStore
    # Verdict-cache column handling for the incremental (`--incremental`)
    # reuse feature. Mixed into {MutantHistoryStore}.
    module VerdictCache
      # The reusable verdicts: hashes are persisted for killed and survived
      # mutants only; every other status stays NULL and always re-executes.
      CACHEABLE_STATUSES = %w[killed survived].freeze

      private

      # Cache-hit mutants (from_cache) were never executed this run, so their
      # covered tests are unknown — carry the stored fingerprints forward
      # instead of recomputing them from empty data (which would wipe them
      # and silently disable reuse after one cached run).
      def verdict_cache_bindings(mutant, existing_row)
        status = mutant.status.to_s
        return [nil, nil] unless CACHEABLE_STATUSES.include?(status)
        return existing_cache_bindings(existing_row) if from_cache?(mutant)
        return killed_cache_bindings(mutant) if status == "killed"

        survived_cache_bindings(mutant, existing_row)
      end

      def killed_cache_bindings(mutant)
        [
          VerdictFingerprint.subject_source_hash(mutant),
          VerdictFingerprint.tests_fingerprint(covered_tests_for(mutant), context_sha: reuse_context&.fingerprint)
        ]
      end

      # Survived rows fingerprint the full-map intersection set — the same
      # set the incremental filter recomputes live — never Mutant#covered_by,
      # which reflects selector fallback and test_excludes and would
      # permanently mismatch the live set. When the fingerprint cannot be
      # recomputed (no per-test map, recipe stubs without a source range),
      # the previously stored bindings are kept, but only from a survived
      # row of the same subject source: a killed row's or an edited method's
      # fingerprints would vouch for a state this survivor never ran in.
      def survived_cache_bindings(mutant, existing_row)
        bindings = [
          VerdictFingerprint.subject_source_hash(mutant),
          survived_tests_fingerprint(mutant)
        ]
        return bindings unless bindings.any?(&:nil?)
        return [nil, nil] unless carry_survived_bindings?(bindings.first, existing_row)

        existing_cache_bindings(existing_row)
      end

      def carry_survived_bindings?(source_hash, existing_row)
        return false unless existing_row && existing_row["current_status"] == "survived"

        source_hash.nil? || source_hash == existing_row["subject_source_hash"]
      end

      def survived_tests_fingerprint(mutant)
        return nil unless per_test_coverage

        VerdictFingerprint.survivor_tests_fingerprint(
          per_test_coverage.tests_covering(mutant),
          context_sha: reuse_context&.fingerprint
        )
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
