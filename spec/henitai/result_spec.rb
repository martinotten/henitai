# frozen_string_literal: true

require "spec_helper"
require "securerandom"
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

  def sample_location(path)
    {
      file: path,
      start_line: 2,
      end_line: 2,
      start_col: 0,
      end_col: 20
    }
  end

  def build_mutant(status:, duration: nil)
    Dir.mktmpdir do |dir|
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

  it "calculates mutation score with excluded statuses removed" do
    expect(result(scoring_mutants).mutation_score).to eq(75.0)
  end

  it "calculates mutation score indicator from killed mutants only" do
    expect(result(scoring_mutants).mutation_score_indicator).to eq(12.5)
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

  it "omits equivalence uncertainty when there are no live mutants" do
    expect(
      result([status_mutant(:ignored), status_mutant(:equivalent)]).scoring_summary
    ).to eq(
      mutation_score: nil,
      mutation_score_indicator: 0.0,
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
end
