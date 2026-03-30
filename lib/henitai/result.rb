# frozen_string_literal: true

module Henitai
  # Aggregates the outcome of a complete mutation testing run.
  #
  # Provides metrics and the serialised Stryker mutation-testing-report-schema
  # JSON payload. The schema version follows stryker-mutator/mutation-testing-elements.
  class Result
    SCHEMA_VERSION = "3"

    attr_reader :mutants, :started_at, :finished_at

    def initialize(mutants:, started_at:, finished_at:)
      @mutants     = mutants
      @started_at  = started_at
      @finished_at = finished_at
    end

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

      (detected.to_f / valid.count * 100).round(2)
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

      (killed.to_f / mutants.count * 100).round(2)
    end

    # @return [Float] duration in seconds
    def duration
      finished_at - started_at
    end

    # Serialise to Stryker mutation-testing-report-schema JSON (v3).
    # @return [Hash]
    def to_stryker_schema
      {
        schemaVersion: SCHEMA_VERSION,
        thresholds: { high: 80, low: 60 },
        files: build_files_section
      }
    end

    private

    def build_files_section
      mutants.group_by { |m| m.location[:file] }.transform_values do |file_mutants|
        source = File.read(file_mutants.first.location[:file]) rescue ""
        {
          language: "ruby",
          source:,
          mutants: file_mutants.map { |m| mutant_to_schema(m) }
        }
      end
    end

    def mutant_to_schema(mutant)
      {
        id:          mutant.id,
        mutatorName: mutant.operator,
        replacement: Unparser.unparse(mutant.mutated_node),
        location: {
          start: { line: mutant.location[:start_line], column: mutant.location[:start_col] },
          end:   { line: mutant.location[:end_line],   column: mutant.location[:end_col] }
        },
        status:       stryker_status(mutant.status),
        description:  mutant.description,
        duration:     mutant.duration&.then { |d| (d * 1000).round }
      }.compact
    end

    def stryker_status(status)
      # :equivalent wird als "Ignored" serialisiert — das Stryker-Schema kennt keinen
      # Equivalent-Status. Die interne Unterscheidung (für MS vs. MSI) bleibt im Result-Objekt.
      {
        killed:        "Killed",
        survived:      "Survived",
        timeout:       "Timeout",
        no_coverage:   "NoCoverage",
        ignored:       "Ignored",
        equivalent:    "Ignored",
        compile_error: "CompileError",
        runtime_error: "RuntimeError",
        pending:       "Pending"
      }.fetch(status, "Pending")
    end
  end
end
