# frozen_string_literal: true

require "parser/current"
require "spec_helper"

RSpec.describe Henitai::Mutant do
  def build_mutant(precomputed_stable_id: nil, precomputed_activation_source: nil)
    described_class.new(
      subject: Henitai::Subject.new(namespace: "Sample", method_name: "alpha"),
      operator: "ArithmeticOperator",
      nodes: {
        original: Parser::AST::Node.new(:int, [1]),
        mutated: Parser::AST::Node.new(:int, [2])
      },
      description: "replaced 1 with 2",
      location: {},
      precomputed_stable_id:,
      precomputed_activation_source:
    )
  end

  it "reports killed status" do
    mutant = build_mutant
    mutant.status = :killed

    expect(mutant.killed?).to be(true)
  end

  it "reports survived status" do
    mutant = build_mutant
    mutant.status = :survived

    expect(mutant.survived?).to be(true)
  end

  it "reports pending status" do
    mutant = build_mutant

    expect(mutant.pending?).to be(true)
  end

  it "reports ignored status" do
    mutant = build_mutant
    mutant.status = :ignored

    expect(mutant.ignored?).to be(true)
  end

  it "reports equivalent status" do
    mutant = build_mutant
    mutant.status = :equivalent

    expect(mutant.equivalent?).to be(true)
  end

  describe "#stable_id" do
    it "returns a 64-character hex string" do
      expect(build_mutant.stable_id).to match(/\A[0-9a-f]{64}\z/)
    end

    it "delegates to MutantIdentity" do
      mutant = build_mutant
      expect(mutant.stable_id).to eq(Henitai::MutantIdentity.stable_id(mutant))
    end

    it "memoizes the result" do
      mutant = build_mutant
      expect(mutant.stable_id).to equal(mutant.stable_id)
    end

    it "returns precomputed_stable_id when provided, skipping MutantIdentity" do
      mutant = build_mutant(precomputed_stable_id: "precomputed-hex")
      expect(mutant.stable_id).to eq("precomputed-hex")
    end
  end

  describe "#precomputed_activation_source" do
    it "is nil by default" do
      expect(build_mutant.precomputed_activation_source).to be_nil
    end

    it "can be provided and read back" do
      mutant = build_mutant(precomputed_activation_source: "define_method(:foo) do\n  nil\nend\n")
      expect(mutant.precomputed_activation_source).to eq("define_method(:foo) do\n  nil\nend\n")
    end
  end

  it "formats itself with operator, location, and description" do
    mutant = described_class.new(
      subject: Henitai::Subject.new(namespace: "Sample", method_name: "alpha"),
      operator: "ArithmeticOperator",
      nodes: {
        original: Parser::AST::Node.new(:int, [1]),
        mutated: Parser::AST::Node.new(:int, [2])
      },
      description: "replaced 1 with 2",
      location: {
        file: "lib/sample.rb",
        start_line: 12
      }
    )

    expect(mutant.to_s).to eq("ArithmeticOperator@lib/sample.rb:12 \u2014 replaced 1 with 2")
  end
end
