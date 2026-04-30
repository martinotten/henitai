# frozen_string_literal: true

require "parser/current"
require "spec_helper"

RSpec.describe Henitai::MutantIdentity do
  def build_mutant(
    operator: "ArithmeticOperator",
    description: "replaced + with -",
    mutated_source: "1 - 2",
    location: { file: "lib/sample.rb", start_line: 2, end_line: 2, start_col: 0, end_col: 5 }
  )
    subject = Henitai::Subject.new(namespace: "Sample", method_name: "value")
    node = Parser::CurrentRuby.parse(mutated_source)
    Henitai::Mutant.new(
      subject:,
      operator:,
      nodes: { original: node, mutated: node },
      description:,
      location:
    )
  end

  describe ".stable_id" do
    it "returns a 64-character hex SHA256 string" do
      expect(described_class.stable_id(build_mutant)).to match(/\A[0-9a-f]{64}\z/)
    end

    it "returns the same id for two mutants with identical inputs" do
      first_id  = described_class.stable_id(build_mutant)
      second_id = described_class.stable_id(build_mutant)
      expect(first_id).to eq(second_id)
    end

    it "returns a different id when the operator changes" do
      expect(described_class.stable_id(build_mutant(operator: "ArithmeticOperator")))
        .not_to eq(described_class.stable_id(build_mutant(operator: "EqualityOperator")))
    end

    it "returns a different id when the mutated source changes" do
      expect(described_class.stable_id(build_mutant(mutated_source: "1 - 2")))
        .not_to eq(described_class.stable_id(build_mutant(mutated_source: "1 * 2")))
    end

    it "returns the same id when only line numbers change" do
      first = build_mutant(location: { file: "lib/sample.rb", start_line: 2, end_line: 2, start_col: 0, end_col: 5 })
      second = build_mutant(location: { file: "lib/sample.rb", start_line: 20, end_line: 20, start_col: 0, end_col: 5 })

      expect(described_class.stable_id(first)).to eq(described_class.stable_id(second))
    end
  end
end
