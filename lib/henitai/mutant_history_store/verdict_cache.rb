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
          VerdictFingerprint.tests_fingerprint(covered_tests_for(mutant))
        ]
      end

      # Survived rows fingerprint the full-map intersection set — the same
      # set the incremental filter recomputes live — never Mutant#covered_by,
      # which reflects selector fallback and test_excludes and would
      # permanently mismatch the live set. When the fingerprint cannot be
      # recomputed (no per-test map, recipe stubs without a source range),
      # the previously stored bindings are kept: the filter re-validates
      # everything live before reuse, so a carried-forward fingerprint can
      # never validate a changed state.
      def survived_cache_bindings(mutant, existing_row)
        bindings = [
          VerdictFingerprint.subject_source_hash(mutant),
          survived_tests_fingerprint(mutant)
        ]
        return bindings unless bindings.any?(&:nil?)

        existing_cache_bindings(existing_row)
      end

      def survived_tests_fingerprint(mutant)
        return nil unless per_test_coverage

        VerdictFingerprint.survivor_tests_fingerprint(
          per_test_coverage.tests_covering(mutant),
          dependency_sha: recording_dependency_sha
        )
      end

      # One dependency sha per record call set, computed lazily so runs
      # without survivors never touch the dependency files.
      def recording_dependency_sha
        @recording_dependency_sha ||= VerdictFingerprint.dependency_fingerprint
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
