# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "parser/current"

RSpec.describe Henitai::MutantHistoryStore do
  def build_subject
    Henitai::Subject.new(namespace: "Sample", method_name: "value")
  end

  def build_location
    {
      file: "lib/sample.rb",
      start_line: 2,
      end_line: 2,
      start_col: 0,
      end_col: 5
    }
  end

  # rubocop:disable Metrics/MethodLength
  def build_mutant(status:, mutated_source: "1 + 0")
    Struct.new(
      :subject,
      :operator,
      :description,
      :location,
      :status,
      :mutated_node
    ) do
      def killed?
        status == :killed
      end

      def survived?
        status == :survived
      end

      def equivalent?
        status == :equivalent
      end
    end.new(
      build_subject,
      "ArithmeticOperator",
      "replaced + with -",
      build_location,
      status,
      Parser::CurrentRuby.parse(mutated_source)
    )
  end
  # rubocop:enable Metrics/MethodLength

  def build_result(mutants, summary)
    Struct.new(:mutants, :scoring_summary).new(mutants, summary)
  end

  it "returns an empty report before any runs are recorded" do
    Dir.mktmpdir do |dir|
      report = described_class.new(path: File.join(dir, "mutation-history.sqlite3")).trend_report

      expect(
        [
          report[:generatedAt].match?(/\A\d{4}-\d{2}-\d{2}T/),
          report[:runs],
          report[:mutants]
        ]
      ).to eq([true, [], []])
    end
  end

  it "records run summaries" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          {
            mutation_score: 80.0,
            mutation_score_indicator: 40.0,
            equivalence_uncertainty: "~10-15% of live mutants"
          }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
      )

      expect(store.trend_report[:runs].first).to eq(
        version: "1.0.0",
        recordedAt: "2026-01-01T12:00:00Z",
        mutationScore: 80.0,
        mutationScoreIndicator: 40.0,
        equivalenceUncertainty: "~10-15% of live mutants",
        totalMutants: 1,
        killedMutants: 0,
        survivedMutants: 1,
        timeoutMutants: 0,
        equivalentMutants: 0
      )
    end
  end

  it "generates a 64-character hexadecimal mutant ID" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      expect(store.trend_report[:mutants].first[:mutantId]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  it "returns status history entries with symbol keys" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      store.record(
        build_result(
          [build_mutant(status: :survived)],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      entry = store.trend_report[:mutants].first[:statusHistory].first
      expect(entry).to have_key(:status)
      expect(entry).not_to have_key("status")
    end
  end

  it "appends mutant history across repeated runs" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      mutant = build_mutant(status: :survived)

      store.record(
        build_result(
          [mutant],
          {
            mutation_score: 80.0,
            mutation_score_indicator: 40.0,
            equivalence_uncertainty: "~10-15% of live mutants"
          }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
      )

      mutant.status = :killed

      store.record(
        build_result(
          [mutant],
          {
            mutation_score: 90.0,
            mutation_score_indicator: 45.0,
            equivalence_uncertainty: nil
          }
        ),
        version: "1.1.0",
        recorded_at: Time.utc(2026, 1, 2, 12, 0, 0)
      )

      mutant_report = store.trend_report[:mutants].first

      expect(
        [
          mutant_report[:currentStatus],
          mutant_report[:daysAlive],
          mutant_report[:statusHistory].map { |entry| entry[:status] }
        ]
      ).to eq(["killed", 1, %w[survived killed]])
    end
  end
end
