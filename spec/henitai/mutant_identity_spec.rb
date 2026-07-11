# frozen_string_literal: true

require "parser/current"
require "spec_helper"

RSpec.describe Henitai::MutantIdentity do
  def build_mutant(
    operator: "ArithmeticOperator",
    description: "replaced + with -",
    mutated_source: "1 - 2",
    location: { file: "lib/sample.rb", start_line: 2, end_line: 2, start_col: 0, end_col: 5 },
    subject_range: nil
  )
    subject = if subject_range
                Henitai::Subject.new(namespace: "Sample", method_name: "value",
                                     source_location: { file: location[:file], range: subject_range })
              else
                Henitai::Subject.new(namespace: "Sample", method_name: "value")
              end
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

    it "returns the same id when the whole subject drifts by a constant line offset" do
      first = build_mutant(
        location: { file: "lib/sample.rb", start_line: 10, end_line: 10, start_col: 4, end_col: 9 },
        subject_range: (5..15)
      )
      second = build_mutant(
        location: { file: "lib/sample.rb", start_line: 30, end_line: 30, start_col: 4, end_col: 9 },
        subject_range: (25..35)
      )

      expect(described_class.stable_id(first)).to eq(described_class.stable_id(second))
    end

    it "returns a different id for two same-signature mutants at distinct call sites in one subject" do
      first = build_mutant(
        operator: "MethodExpression",
        description: "replaced method call with nil",
        mutated_source: "nil",
        location: { file: "lib/sample.rb", start_line: 6, end_line: 6, start_col: 4, end_col: 20 },
        subject_range: (5..15)
      )
      second = build_mutant(
        operator: "MethodExpression",
        description: "replaced method call with nil",
        mutated_source: "nil",
        location: { file: "lib/sample.rb", start_line: 9, end_line: 9, start_col: 8, end_col: 24 },
        subject_range: (5..15)
      )

      expect(described_class.stable_id(first)).not_to eq(described_class.stable_id(second))
    end
  end

  describe ".legacy_stable_id" do
    it "returns a 64-character hex SHA256 string" do
      expect(described_class.legacy_stable_id(build_mutant)).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
