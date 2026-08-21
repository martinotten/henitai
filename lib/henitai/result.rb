# frozen_string_literal: true

require "securerandom"
require_relative "mutant_identity"
require_relative "unparse_helper"

module Henitai
  # Aggregates the outcome of a complete mutation testing run.
  #
  # Provides metrics and the serialised Stryker mutation-testing-report-schema
  # JSON payload. The schema version follows stryker-mutator/mutation-testing-elements.
  class Result
    include UnparseHelper

    SCHEMA_VERSION = "1.0"
    DEFAULT_THRESHOLDS = { high: 80, low: 60 }.freeze

    # Which outcomes count as "the test suite detected this mutant" for the MS
    # numerator. Duplicated from Configuration rather than read from it: Result
    # is a domain object and must not depend on configuration loading. The same
    # arrangement already exists for DEFAULT_THRESHOLDS, and result_spec asserts
    # the two constants stay equal.
    DEFAULT_COVERAGE_CRITERIA = {
      test_result: true,
      timeout: true,
      process_abort: true
    }.freeze

    # Maps each criterion to the mutant status it governs. process_abort has no
    # producer in lib/ yet -- nothing classifies a mutant as :runtime_error --
    # so that entry is forward-looking wiring rather than a live code path.
    CRITERION_STATUSES = {
      test_result: :killed,
      timeout: :timeout,
      process_abort: :runtime_error
    }.freeze

    attr_reader :mutants, :started_at, :finished_at, :thresholds, :survivor_stats,
                :session_id, :git_sha, :since, :coverage_criteria

    # @param source_provider [#call] maps a file path to its source string.
    #   Injected so the domain object performs no disk IO; the caller (which
    #   already knows the file paths) supplies the contents. The default
    #   provider returns "" for every file — callers that need real source in
    #   the schema (e.g. the runner) inject a provider primed with file content.
    # @param authoritative [Boolean] whether this run covers the full
    #   configured mutation scope. Authoritative runs fully replace the
    #   canonical report; non-authoritative (subject-scoped, --since,
    #   --survivors-from) runs are merged into it instead — see
    #   CanonicalReportMerger.
    # rubocop:disable Metrics/ParameterLists
    def initialize(mutants:, started_at:, finished_at:, thresholds: nil,
                   partial_rerun: false, survivor_stats: nil,
                   session_id: SecureRandom.uuid, git_sha: nil,
                   source_provider: ->(_file) { "" }, authoritative: true,
                   since: nil, coverage_criteria: nil)
      @mutants         = mutants
      @started_at      = started_at
      @finished_at     = finished_at
      @thresholds      = DEFAULT_THRESHOLDS.merge(thresholds || {})
      @partial_rerun   = partial_rerun
      @survivor_stats  = survivor_stats
      @session_id      = session_id
      @git_sha         = git_sha
      @source_provider = source_provider
      @authoritative   = authoritative
      @since           = since
      @coverage_criteria = DEFAULT_COVERAGE_CRITERIA.merge(coverage_criteria || {})
    end
    # rubocop:enable Metrics/ParameterLists

    def partial_rerun? = @partial_rerun
    def authoritative? = @authoritative

    # @return [Integer] number of killed mutants
    def killed   = mutants.count(&:killed?)

    # @return [Integer] number of survived mutants
    def survived = mutants.count(&:survived?)

    # @return [Integer] number of confirmed equivalent mutants (excluded from MS)
    def equivalent = mutants.count(&:equivalent?)

    # Detected = killed + timeout + runtime_error (alle Zustände die einen Fehler beweisen)
    # @return [Integer]
    def detected
      detected_in(mutants)
    end

    # Mutation Score (MS) — Architektur-Formel aus Abschnitt 6.1:
    #
    #   MS = detected / (total − ignored − no_coverage − compile_error − equivalent)
    #
    # Confirmed equivalent mutants werden aus BEIDEN Seiten der Gleichung entfernt:
    # Sie sind weder im Zähler (nicht detektierbar) noch im Nenner (nicht testbar).
    # Das ist der entscheidende Unterschied zum MSI.
    #
    # @return [Float, nil] 0.0–100.0, nil wenn kein valider Mutant vorhanden
    def mutation_score
      mutation_score_for(mutants)
    end

    # Mutation Score Indicator (MSI) — naive Berechnung ohne Äquivalenz-Bereinigung:
    #
    #   MSI = killed / all_mutants
    #
    # MSI ist immer ≤ MS. Der Unterschied kommuniziert die Äquivalenz-Unsicherheit.
    # Beide Werte MÜSSEN im Report zusammen ausgewiesen werden (Anti-Pattern: nur MS).
    #
    # @return [Float, nil]
    def mutation_score_indicator
      mutation_score_indicator_for(mutants)
    end

    # Scores over only the mutants actually executed this run — verdicts
    # reused from the history store (`--incremental`) excluded. nil when
    # nothing was reused: the combined scores already tell the whole story,
    # and reporters use nil to suppress the extra line.
    #
    # @return [Hash, nil] { mutation_score:, mutation_score_indicator: }
    def executed_scoring_summary
      executed = mutants.reject { |m| m.respond_to?(:from_cache?) && m.from_cache? }
      return nil if executed.size == mutants.size

      {
        mutation_score: mutation_score_for(executed),
        mutation_score_indicator: mutation_score_indicator_for(executed)
      }
    end

    # Compact public summary for reporters.
    # The uncertainty note is intentionally qualitative: equivalent mutants are
    # a known gray area, so the terminal report should communicate that
    # uncertainty instead of pretending to be precise.
    def scoring_summary
      {
        mutation_score: mutation_score,
        mutation_score_indicator: mutation_score_indicator,
        equivalence_uncertainty: equivalence_uncertainty
      }
    end

    # @return [Float] duration in seconds
    def duration
      finished_at - started_at
    end

    # Serialise to Stryker mutation-testing-report-schema JSON (schema 1.0).
    # @return [Hash]
    def to_stryker_schema
      schema = base_schema
      sha = @git_sha
      schema[:gitSha] = sha if sha
      return schema unless partial_rerun?

      schema[:partialRerun] = true
      schema[:unmatchedSurvivorIds] = unmatched_survivor_ids
      schema
    end

    private

    def detected_in(list)
      list.count { |m| detected_statuses.include?(m.status) }
    end

    def detected_statuses
      @detected_statuses ||= CRITERION_STATUSES.filter_map do |criterion, status|
        status if @coverage_criteria[criterion]
      end
    end

    def mutation_score_for(list)
      excluded = %i[ignored no_coverage compile_error equivalent]
      valid = list.reject { |m| excluded.include?(m.status) }
      return nil if valid.empty?

      ((detected_in(list).to_f / valid.count) * 100.0).round(2).to_f
    end

    def mutation_score_indicator_for(list)
      return nil if list.empty?

      ((list.count(&:killed?).to_f / list.count) * 100.0).round(2).to_f
    end

    def base_schema
      { # : Hash[Symbol, untyped]
        schemaVersion: SCHEMA_VERSION,
        sessionId: @session_id,
        thresholds: thresholds,
        files: build_files_section
      }
    end

    def unmatched_survivor_ids
      return survivor_stats.fetch(:unmatched_ids) if survivor_stats

      [] # : Array[String]
    end

    def build_files_section
      mutants.group_by { |m| m.location[:file] }.transform_values do |file_mutants|
        {
          language: "ruby",
          source: @source_provider.call(file_mutants.first.location[:file]),
          mutants: file_mutants.map { |m| mutant_to_schema(m) }
        }
      end
    end

    def mutant_to_schema(mutant)
      {
        id: mutant.id,
        stableId: mutant.stable_id,
        legacyStableId: legacy_stable_id_for(mutant),
        mutatorName: mutant.operator,
        replacement: replacement_for(mutant),
        location: location_for(mutant),
        status: stryker_status(mutant.status),
        statusReason: status_reason_for(mutant),
        fromCache: from_cache_for(mutant),
        description: mutant.description,
        duration: duration_for(mutant)
      }.compact.merge(coverage_schema(mutant))
    end

    def coverage_schema(mutant)
      covered_by = Array(mutant.covered_by).compact
      return {} if covered_by.empty?

      {
        coveredBy: covered_by,
        testsCompleted: mutant.tests_completed || covered_by.size
      }
    end

    def replacement_for(mutant)
      return mutant.mutated_source if mutant.respond_to?(:mutated_source)

      safe_unparse(mutant.mutated_node)
    end

    def location_for(mutant)
      {
        start: line_column(mutant, :start),
        end: line_column(mutant, :end)
      }
    end

    def line_column(mutant, prefix)
      # Stryker schema columns are 1-based; Parser locations are 0-based.
      {
        line: mutant.location.fetch(:"#{prefix}_line"),
        column: mutant.location.fetch(:"#{prefix}_col") + 1
      }
    end

    def duration_for(mutant)
      mutant.duration&.then { |d| (d * 1000).round }
    end

    # Serialized as the schema's statusReason so directive reasons show up
    # next to the Ignored status in the HTML report.
    def status_reason_for(mutant)
      return nil unless mutant.respond_to?(:ignore_reason)

      mutant.ignore_reason
    end

    # Vendored extension field (like stableId): marks verdicts reused from
    # the history store so reports stay honest about what actually executed.
    def from_cache_for(mutant)
      return nil unless mutant.respond_to?(:from_cache?)

      mutant.from_cache? || nil
    end

    def legacy_stable_id_for(mutant)
      return if mutant.respond_to?(:precomputed_stable_id) && mutant.precomputed_stable_id

      MutantIdentity.legacy_stable_id(mutant)
    end

    def equivalence_uncertainty
      return nil if mutation_score.nil?

      "~10-15% of live mutants"
    end

    def stryker_status(status)
      # :equivalent wird als "Ignored" serialisiert — das Stryker-Schema kennt keinen
      # Equivalent-Status. Die interne Unterscheidung (für MS vs. MSI) bleibt im Result-Objekt.
      {
        killed: "Killed",
        survived: "Survived",
        timeout: "Timeout",
        no_coverage: "NoCoverage",
        ignored: "Ignored",
        equivalent: "Ignored",
        compile_error: "CompileError",
        runtime_error: "RuntimeError",
        pending: "Pending"
      }.fetch(status, "Pending")
    end
  end
end
