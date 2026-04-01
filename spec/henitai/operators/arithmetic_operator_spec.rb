# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::ArithmeticOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Calculator", method_name: "calculate")
  end

  def mutate(source)
    described_class.new.mutate(parse(source), subject: mutation_subject).first
  end

  it "declares the arithmetic send node type" do
    expect(described_class.node_types).to eq([:send])
  end

  it "mutates + to -" do
    expect(mutate("a + b")).to have_attributes(
      description: "replaced + with -",
      mutated_node: satisfy { |node| node.children[1] == :- }
    )
  end

  it "mutates - to +" do
    expect(mutate("a - b").mutated_node.children[1]).to eq(:+)
  end

  it "mutates * to /" do
    expect(mutate("a * b").mutated_node.children[1]).to eq(:/)
  end

  it "mutates / to *" do
    expect(mutate("a / b").mutated_node.children[1]).to eq(:*)
  end

  it "mutates ** to *" do
    expect(mutate("a ** b").mutated_node.children[1]).to eq(:*)
  end

  it "mutates % to *" do
    expect(mutate("a % b").mutated_node.children[1]).to eq(:*)
  end

  it "ignores non-arithmetic sends" do
    expect(described_class.new.mutate(parse("a.foo"), subject: mutation_subject)).to eq([])
  end
end
