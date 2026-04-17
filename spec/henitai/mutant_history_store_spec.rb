# frozen_string_literal: true

require "digest"
require "spec_helper"
require "sqlite3"
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
    Struct.new(:mutants, :scoring_summary) do
      def partial_rerun? = false
    end.new(mutants, summary)
  end

  def record_run(store, mutant:, summary:, version:, recorded_at:)
    store.record(
      build_result([mutant], summary),
      version:,
      recorded_at:
    )
  end

  def record_history_chain(store, mutant)
    record_first_history_run(store, mutant)
    mutant.status = :killed
    record_second_history_run(store, mutant)
  end

  def expect_mutant_history(mutant_report)
    expect(mutant_history_values(mutant_report)).to eq(expected_mutant_history_values)
  end

  def record_first_history_run(store, mutant)
    record_run(
      store,
      mutant:,
      summary: {
        mutation_score: 80.0,
        mutation_score_indicator: 40.0,
        equivalence_uncertainty: "~10-15% of live mutants"
      },
      version: "1.0.0",
      recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
    )
  end

  def record_second_history_run(store, mutant)
    record_run(
      store,
      mutant:,
      summary: {
        mutation_score: 90.0,
        mutation_score_indicator: 45.0,
        equivalence_uncertainty: nil
      },
      version: "1.1.0",
      recorded_at: Time.utc(2026, 1, 2, 12, 0, 0)
    )
  end

  def mutant_history_values(mutant_report)
    [
      mutant_report[:currentStatus],
      mutant_report[:daysAlive],
      mutant_report[:firstSeenVersion],
      mutant_report[:firstSeenAt],
      mutant_report[:lastSeenVersion],
      mutant_report[:lastSeenAt],
      mutant_report[:statusHistory].map { |entry| entry[:status] }
    ]
  end

  def expected_mutant_history_values
    [
      "killed",
      1,
      "1.0.0",
      "2026-01-01T12:00:00Z",
      "1.1.0",
      "2026-01-02T12:00:00Z",
      %w[survived killed]
    ]
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

  it "uses a stable SHA-256 mutant ID" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      mutant = build_mutant(status: :survived, mutated_source: "1 - 0")

      store.record(
        build_result(
          [mutant],
          { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
        ),
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1)
      )

      expected_id = Digest::SHA256.hexdigest(
        [
          mutant.subject.expression,
          mutant.operator,
          mutant.description,
          mutant.location[:file],
          Unparser.unparse(mutant.mutated_node)
        ].join("\0")
      )

      expect(store.trend_report[:mutants].first[:mutantId]).to eq(expected_id)
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
      aggregate_failures do
        expect(entry).to have_key(:status)
        expect(entry).not_to have_key("status")
      end
    end
  end

  it "appends mutant history across repeated runs" do
    Dir.mktmpdir do |dir|
      store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
      mutant = build_mutant(status: :survived)

      record_history_chain(store, mutant)
      expect_mutant_history(store.trend_report[:mutants].first)
    end
  end

  describe "partial rerun result" do
    def partial_result(mutants)
      result = build_result(
        mutants,
        { mutation_score: 80.0, mutation_score_indicator: 40.0, equivalence_uncertainty: nil }
      )
      allow(result).to receive(:partial_rerun?).and_return(true)
      result
    end

    it "does not insert a runs row for a partial rerun" do
      Dir.mktmpdir do |dir|
        store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
        store.record(partial_result([build_mutant(status: :survived)]), version: "0.1.0")

        db = SQLite3::Database.new(File.join(dir, "mutation-history.sqlite3"))
        db.results_as_hash = true
        count = db.get_first_value("SELECT COUNT(*) FROM runs")
        db.close

        expect(count).to eq(0)
      end
    end

    it "still upserts mutant rows for a partial rerun" do
      Dir.mktmpdir do |dir|
        store = described_class.new(path: File.join(dir, "mutation-history.sqlite3"))
        mutants = [build_mutant(status: :survived)]
        store.record(partial_result(mutants), version: "0.1.0")

        db = SQLite3::Database.new(File.join(dir, "mutation-history.sqlite3"))
        db.results_as_hash = true
        count = db.get_first_value("SELECT COUNT(*) FROM mutants")
        db.close

        expect(count).to eq(1)
      end
    end
  end
end
