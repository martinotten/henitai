# frozen_string_literal: true

require "json"
require "json_schemer"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Result do
  def sample_source
    <<~RUBY
      class Sample
        def answer = 1 + 2
      end
    RUBY
  end

  def result_schema_path
    File.expand_path("../fixtures/mutation-testing-report-schema-3.5.1.json", __dir__)
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

  def sample_mutant(path)
    Henitai::Mutant.new(**sample_mutant_attributes(path))
  end

  def sample_mutant_attributes(path)
    {
      subject: sample_subject(path),
      operator: "ArithmeticOperator",
      nodes: sample_nodes(path),
      description: "replaced + with -",
      location: sample_location(path)
    }
  end

  def sample_result(path)
    mutant = sample_mutant(path)
    mutant.status = :killed

    described_class.new(
      mutants: [mutant],
      started_at: Time.at(0),
      finished_at: Time.at(1)
    )
  end

  it "validates the generated report against the Stryker schema" do
    schema = JSON.parse(File.read(result_schema_path))
    schemer = JSONSchemer.schema(schema)

    Dir.mktmpdir do |dir|
      path = write_sample_file(dir)

      expect(schemer.valid?(sample_result(path).to_stryker_schema)).to be(true)
    end
  end

  it "records per-file provenance and the complete files of a non-authoritative run", :aggregate_failures do
    schemer = JSONSchemer.schema(JSON.parse(File.read(result_schema_path)))

    Dir.mktmpdir do |dir|
      path = write_sample_file(dir)
      mutant = sample_mutant(path)
      mutant.status = :killed
      result = described_class.new(mutants: [mutant], started_at: Time.at(0), finished_at: Time.at(1),
                                   session_id: "S1", git_sha: "abc", authoritative: false,
                                   complete_files: [path, "gone.rb"])
      schema = result.to_stryker_schema

      expect(schema[:files][path]).to include(sessionId: "S1", gitSha: "abc")
      expect(schema[:completeFiles]).to eq([path, "gone.rb"])
      expect(schemer.valid?(JSON.parse(JSON.generate(schema)))).to be(true)
    end
  end

  it "omits completeFiles for an authoritative run" do
    result = described_class.new(mutants: [], started_at: Time.at(0), finished_at: Time.at(1),
                                 complete_files: ["a.rb"])

    expect(result.to_stryker_schema).not_to have_key(:completeFiles)
  end
end
