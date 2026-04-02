# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant do
  def build_mutant
    described_class.new(
      subject: Henitai::Subject.new(namespace: "Sample", method_name: "alpha"),
      operator: "ArithmeticOperator",
      nodes: {
        original: Parser::AST::Node.new(:int, [1]),
        mutated: Parser::AST::Node.new(:int, [2])
      },
      description: "replaced 1 with 2",
      location: {}
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
end
