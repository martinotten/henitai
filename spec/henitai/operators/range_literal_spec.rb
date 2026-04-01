# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::RangeLiteral do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "range")
  end

  def mutate(source)
    node = %i[irange erange].flat_map { |type| find_nodes(parse(source), type) }.first

    described_class.new.mutate(node, subject: mutation_subject).first
  end

  it "declares the range node types" do
    expect(described_class.node_types).to eq(%i[irange erange])
  end

  it "mutates inclusive ranges to exclusive ranges" do
    mutant = mutate("1..5")

    expect(mutant).to have_attributes(
      description: "replaced .. with ...",
      mutated_node: satisfy { |node| node.type == :erange }
    )
  end

  it "mutates exclusive ranges to inclusive ranges" do
    mutant = mutate("1...5")

    expect(mutant).to have_attributes(
      description: "replaced ... with ..",
      mutated_node: satisfy { |node| node.type == :irange }
    )
  end

  it "preserves beginless ranges" do
    mutant = mutate("..5")

    expect(mutant.mutated_node.children.first).to be_nil
  end

  it "preserves endless ranges" do
    mutant = mutate("1..")

    expect(mutant.mutated_node.children.last).to be_nil
  end

  it "ignores non-range nodes" do
    node = find_nodes(parse("value"), :send).first

    expect(described_class.new.mutate(node, subject: mutation_subject)).to eq([])
  end
end
