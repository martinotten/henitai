# frozen_string_literal: true

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

    attr_reader :mutants, :started_at, :finished_at, :thresholds, :survivor_stats

    # rubocop:disable Metrics/ParameterLists
    def initialize(mutants:, started_at:, finished_at:, thresholds: nil,
                   partial_rerun: false, survivor_stats: nil)
      @mutants        = mutants
      @started_at     = started_at
      @finished_at    = finished_at
      @thresholds     = DEFAULT_THRESHOLDS.merge(thresholds || {})
      @partial_rerun  = partial_rerun
      @survivor_stats = survivor_stats
    end
    # rubocop:enable Metrics/ParameterLists

    def partial_rerun? = @partial_rerun

    # @return [Integer] number of killed mutants
    def killed   = mutants.count(&:killed?)

    # @return [Integer] number of survived mutants
    def survived = mutants.count(&:survived?)

    # @return [Integer] number of confirmed equivalent mutants (excluded from MS)
    def equivalent = mutants.count(&:equivalent?)

    # Detected = killed + timeout + runtime_error (alle Zustände die einen Fehler beweisen)
    # @return [Integer]
    def detected
      mutants.count { |m| %i[killed timeout runtime_error].include?(m.status) }
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
      excluded = %i[ignored no_coverage compile_error equivalent]
      valid = mutants.reject { |m| excluded.include?(m.status) }
      return nil if valid.empty?

      ((detected.to_f / valid.count) * 100.0).round(2).to_f
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
      return nil if mutants.empty?

      ((killed.to_f / mutants.count) * 100.0).round(2).to_f
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
      base_schema.tap do |s|
        next unless partial_rerun?

        s[:partialRerun] = true
        s[:unmatchedSurvivorIds] = unmatched_survivor_ids
      end
    end

    private

    def base_schema
      { # : Hash[Symbol, untyped]
        schemaVersion: SCHEMA_VERSION,
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
        source = begin
          File.read(file_mutants.first.location[:file])
        rescue StandardError
          ""
        end
        {
          language: "ruby",
          source:,
          mutants: file_mutants.map { |m| mutant_to_schema(m) }
        }
      end
    end

    def mutant_to_schema(mutant)
      {
        id: mutant.id,
        stableId: mutant.stable_id,
        mutatorName: mutant.operator,
        replacement: replacement_for(mutant),
        location: location_for(mutant),
        status: stryker_status(mutant.status),
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
