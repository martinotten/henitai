# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "parser/current"
require "tmpdir"
require "unparser"

RSpec.describe Henitai::Result do
  def sample_source
    <<~RUBY
      class Sample
        def answer = 1 + 2
      end
    RUBY
  end

  def write_sample_file(dir)
    path = File.join(dir, "sample.rb")
    File.write(path, sample_source)
    path
  end

  def sample_subject(path)
    Henitai::Subject.new(
      namespace: "Sample",
      method_name: "answer",
      source_location: {
        file: path,
        range: 1..3
      }
    )
  end

  def sample_nodes(path)
    ast = Henitai::SourceParser.parse(sample_source, path:)
    {
      original: ast,
      mutated: ast
    }
  end

  # rubocop:disable Metrics/MethodLength
  def unsupported_mutant(status:)
    node = Parser::AST::Node.new(:dstr, [])
    mutant = Henitai::Mutant.new(
      subject: Henitai::Subject.new(
        namespace: "Sample",
        method_name: "message"
      ),
      operator: "StringLiteral",
      nodes: {
        original: node,
        mutated: node
      },
      description: "removed interpolation from string",
      location: {
        file: "(string)",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 30
      }
    )
    mutant.status = status
    mutant
  end
  # rubocop:enable Metrics/MethodLength

  def sample_location(path)
    {
      file: path,
      start_line: 2,
      end_line: 2,
      start_col: 0,
      end_col: 20
    }
  end

  def build_mutant(status:, duration: nil, dir: nil)
    return build_mutant_in_dir(status:, duration:, dir:) if dir

    Dir.mktmpdir do |temp_dir|
      build_mutant(status:, duration:, dir: temp_dir)
    end
  end

  def build_mutant_in_dir(status:, duration:, dir:)
    path = write_sample_file(dir)
    mutant = Henitai::Mutant.new(
      subject: sample_subject(path),
      operator: "ArithmeticOperator",
      nodes: sample_nodes(path),
      description: "replaced + with -",
      location: sample_location(path)
    )
    mutant.status = status
    mutant.duration = duration
    mutant
  end

  def result(mutants)
    described_class.new(
      mutants:,
      started_at: Time.at(0),
      finished_at: Time.at(1)
    )
  end

  def status_mutant(status)
    Struct.new(:status) do
      def killed?
        status == :killed
      end

      def survived?
        status == :survived
      end

      def equivalent?
        status == :equivalent
      end
    end.new(status)
  end

  def scoring_mutants
    %i[killed timeout runtime_error survived ignored no_coverage compile_error equivalent]
      .map { |status| status_mutant(status) }
  end

  def mutant_statuses(schema)
    schema[:files].values.flat_map do |file|
      file[:mutants].map { |mutant| mutant[:status] }
    end
  end

  it "exposes the mutants collection" do
    mutant = status_mutant(:killed)

    expect(result([mutant]).mutants).to eq([mutant])
  end

  it "exposes the start time" do
    expect(result([]).started_at).to eq(Time.at(0))
  end

  it "exposes the finish time" do
    expect(result([]).finished_at).to eq(Time.at(1))
  end

  it "calculates duration from the provided timestamps" do
    expect(result([]).duration).to eq(1.0)
  end

  it "counts survived mutants" do
    mutants = [status_mutant(:survived), status_mutant(:survived), status_mutant(:killed)]
    expect(result(mutants).survived).to eq(2)
  end

  it "counts equivalent mutants" do
    mutants = [status_mutant(:equivalent), status_mutant(:survived)]
    expect(result(mutants).equivalent).to eq(1)
  end

  it "calculates mutation score with excluded statuses removed" do
    expect(result(scoring_mutants).mutation_score).to eq(75.0)
  end

  it "calculates mutation score indicator from killed mutants only" do
    expect(result(scoring_mutants).mutation_score_indicator).to eq(12.5)
  end

  it "returns nil scores for an empty mutant set" do
    empty_result = result([])

    expect(
      [
        empty_result.mutation_score,
        empty_result.mutation_score_indicator
      ]
    ).to eq([nil, nil])
  end

  it "summarises scoring for reporters" do
    expect(result(scoring_mutants).scoring_summary).to eq(
      mutation_score: 75.0,
      mutation_score_indicator: 12.5,
      equivalence_uncertainty: "~10-15% of live mutants"
    )
  end

  it "serialises the expected schema version" do
    expect(result([build_mutant(status: :pending)]).to_stryker_schema[:schemaVersion]).to eq("1.0")
  end

  it "serialises the Stryker status vocabulary for every mutant status" do
    Dir.mktmpdir do |dir|
      mutants = %i[
        killed
        survived
        timeout
        ignored
        no_coverage
        compile_error
        runtime_error
        equivalent
        pending
        unknown
      ].map { |status| build_mutant(status:, dir:) }

      schema = result(mutants).to_stryker_schema

      expect(mutant_statuses(schema)).to eq(
        %w[
          Killed
          Survived
          Timeout
          Ignored
          NoCoverage
          CompileError
          RuntimeError
          Ignored
          Pending
          Pending
        ]
      )
    end
  end

  it "serialises coveredBy and testsCompleted when test data is present" do
    Dir.mktmpdir do |dir|
      mutant = build_mutant(status: :killed, dir:)
      mutant.covered_by = ["spec/sample_spec.rb"]
      mutant.tests_completed = 1

      schema = result([mutant]).to_stryker_schema
      file = schema[:files].keys.first

      expect(schema[:files][file][:mutants].first).to include(
        coveredBy: ["spec/sample_spec.rb"],
        testsCompleted: 1
      )
    end
  end

  it "omits equivalence uncertainty when there are no live mutants" do
    expect(
      result([status_mutant(:ignored), status_mutant(:equivalent)]).scoring_summary
    ).to eq(
      mutation_score: nil,
      mutation_score_indicator: 0.0,
      equivalence_uncertainty: nil
    )
  end

  it "returns all-nil scoring summary for an empty mutant set" do
    expect(result([]).scoring_summary).to eq(
      mutation_score: nil,
      mutation_score_indicator: nil,
      equivalence_uncertainty: nil
    )
  end

  it "omits nil durations from the serialised mutant payload" do
    schema = result([build_mutant(status: :pending)]).to_stryker_schema
    file = schema[:files].keys.first

    expect(schema[:files][file][:mutants].first.key?(:duration)).to be(false)
  end

  it "serialises durations in milliseconds" do
    schema = result([build_mutant(status: :pending, duration: 1.234)]).to_stryker_schema
    file = schema[:files].keys.first

    expect(schema[:files][file][:mutants].first[:duration]).to eq(1234)
  end

  it "serialises column offsets as 1-based positions" do
    schema = result([build_mutant(status: :pending)]).to_stryker_schema
    file = schema[:files].keys.first
    location = schema[:files][file][:mutants].first[:location]

    expect(location).to eq(
      start: { line: 2, column: 1 },
      end: { line: 2, column: 21 }
    )
  end

  it "falls back to the node type when a replacement cannot be unparsed" do
    mutant = unsupported_mutant(status: :pending)
    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_raise(StandardError, "boom")
    schema = result([mutant]).to_stryker_schema
    file = schema[:files].keys.first

    expect(schema[:files][file][:mutants].first[:replacement]).to eq("dstr")
  end
end
