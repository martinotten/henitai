# frozen_string_literal: true

# Reporter integration examples naturally use a compact fixture helper and
# multiple assertions against the produced artifacts.
# rubocop:disable Metrics/MethodLength, RSpec/MultipleExpectations

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Reporter::Json do
  def build_config(reports_dir:)
    Struct.new(:reports_dir).new(reports_dir)
  end

  def build_result(schema:)
    Struct.new(:to_stryker_schema).new(schema)
  end

  def build_history_mutant
    subject = Henitai::Subject.new(namespace: "Sample", method_name: "value")
    mutant = Struct.new(
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
    end

    mutant.new(
      subject,
      "ArithmeticOperator",
      "replaced + with -",
      {
        file: "lib/sample.rb",
        start_line: 2,
        end_line: 2,
        start_col: 0,
        end_col: 5
      },
      :survived,
      Parser::CurrentRuby.parse("1 - 0")
    )
  end

  def build_history_result
    Struct.new(:mutants, :scoring_summary).new(
      [build_history_mutant],
      {
        mutation_score: 80.0,
        mutation_score_indicator: 40.0,
        equivalence_uncertainty: "~10-15% of live mutants"
      }
    )
  end

  it "writes mutation-report.json to the configured reports directory" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(File).to exist(report_path)
    end
  end

  it "writes the schema payload as JSON" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-report.json")

      expect(JSON.parse(File.read(report_path), symbolize_names: true)).to eq(schema)
    end
  end

  it "writes mutation-history.json from the sqlite history store" do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "nested", "reports")
      store = Henitai::MutantHistoryStore.new(
        path: File.join(reports_dir, "mutation-history.sqlite3")
      )
      store.record(
        build_history_result,
        version: "1.0.0",
        recorded_at: Time.utc(2026, 1, 1, 12, 0, 0)
      )

      schema = {
        schemaVersion: "1.0",
        thresholds: { high: 80, low: 60 },
        files: {}
      }

      described_class.new(config: build_config(reports_dir:)).report(build_result(schema:))

      report_path = File.join(reports_dir, "mutation-history.json")
      history = JSON.parse(File.read(report_path), symbolize_names: true)

      expect(history[:runs].first).to include(
        version: "1.0.0",
        mutationScore: 80.0
      )
      expect(history[:mutants].first).to include(
        currentStatus: "survived",
        daysAlive: 0
      )
    end
  end
end
# rubocop:enable Metrics/MethodLength, RSpec/MultipleExpectations
