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

  it "returns nil and a score when evaluating mutation score" do
    expect(
      [
        result([build_mutant(status: :ignored), build_mutant(status: :equivalent)]).mutation_score,
        result([build_mutant(status: :killed), build_mutant(status: :survived)]).mutation_score
      ]
    ).to eq([nil, 50.0])
  end

  it "returns nil and a score when evaluating mutation score indicator" do
    expect(
      [
        result([]).mutation_score_indicator,
        result([build_mutant(status: :killed), build_mutant(status: :survived)]).mutation_score_indicator
      ]
    ).to eq([nil, 50.0])
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
