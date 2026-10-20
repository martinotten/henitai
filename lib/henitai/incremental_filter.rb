# frozen_string_literal: true

require_relative "signature_line"
require_relative "verdict_fingerprint"

module Henitai
  # Marks mutants whose verdict from a prior run is still valid so
  # `--incremental` runs skip re-executing them (Gate 3.5, opt-in).
  #
  # Reuse rules (conservative — any doubt resolves to re-execution):
  #
  #   * Both verdicts: the stored {ReuseContext} fingerprint (test
  #     dependencies, verdict-relevant configuration, henitai version) must
  #     equal the current one. Rows recorded without a context are never
  #     reused.
  #   * Killed: the stored verdict must carry both fingerprints, and both the
  #     subject's source and every recorded covering test file must be
  #     byte-identical to what was recorded. Killed is monotone, so no live
  #     coverage is needed.
  #   * Survived: additionally the LIVE covering set (the full-map
  #     intersection computed via {PerTestCoverage}) must equal the recorded
  #     set in membership — a new or edited test reaching the mutant always
  #     forces a re-run (ADR-11). Without a live per-test map or a context,
  #     survivors always re-execute.
  #
  # Timeouts, errors, unknown ids and legacy rows always re-execute.
  class IncrementalFilter
    def initialize(history_store:, per_test_coverage: nil, reuse_context: nil)
      @history_store = history_store
      @per_test_coverage = per_test_coverage
      @reuse_context = reuse_context
    end

    # @return [Array<Mutant>] the same collection; cache hits get the stored
    #   status (:killed or :survived) and from_cache = true.
    def apply(mutants)
      collection = Array(mutants)
      ambiguous = ambiguous_stable_ids(collection)
      collection.each do |mutant|
        next unless mutant.pending?
        next if ambiguous.include?(mutant.stable_id)

        status = reusable_status(mutant)
        next unless status

        mutant.status = status
        mutant.from_cache = true if mutant.respond_to?(:from_cache=)
      end

      mutants
    end

    private

    attr_reader :history_store, :per_test_coverage, :reuse_context

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

    def reusable_status(mutant)
      verdict = history_store.verdict_for(mutant.stable_id)
      return nil unless verdict

      case verdict.fetch(:status)
      when :killed
        :killed if killed_reusable?(mutant, verdict)
      when :survived
        :survived if survived_reusable?(mutant, verdict)
      end
    end

    def killed_reusable?(mutant, verdict)
      subject_source_unchanged?(mutant, verdict) &&
        VerdictFingerprint.tests_fingerprint_current?(
          verdict.fetch(:covered_tests_fingerprint), context_sha: context_sha
        )
    end

    # The filter checks per-test map availability itself instead of trusting
    # the bootstrap's readiness skip: integrations without per-test support
    # or a missing/empty map mean the live covering set is unknowable, and
    # unknowable means re-execute.
    def survived_reusable?(mutant, verdict)
      return false unless per_test_coverage&.available?
      return false if SignatureLine.on?(mutant)
      return false unless subject_source_unchanged?(mutant, verdict)

      VerdictFingerprint.survivor_fingerprint_current?(
        verdict.fetch(:covered_tests_fingerprint),
        live_paths: per_test_coverage.tests_covering(mutant),
        context_sha: context_sha
      )
    end

    def context_sha = reuse_context&.fingerprint

    def subject_source_unchanged?(mutant, verdict)
      current = VerdictFingerprint.subject_source_hash(mutant)
      !current.nil? && current == verdict.fetch(:subject_source_hash)
    end
  end
end
