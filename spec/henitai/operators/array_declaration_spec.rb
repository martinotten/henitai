# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::ArrayDeclaration do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "array")
  end

  def mutate(source)
    node = find_nodes(parse(source), :array).first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the array node type" do
    expect(described_class.node_types).to eq([:array])
  end

  it "replaces empty arrays with a nil element" do
    mutant = mutate("[]").first

    expect(mutant).to have_attributes(
      description: "replaced empty array with [nil]",
      mutated_node: satisfy { |node| node.children.first.type == :nil }
    )
  end

  it "replaces non-empty arrays with an empty array" do
    mutant = mutate("[1, 2]").first

    expect(mutant).to have_attributes(
      description: "replaced array with empty array",
      mutated_node: satisfy { |node| node.children.empty? }
    )
  end

  it "removes each array element independently" do
    mutants = mutate("[1, 2]")

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced array with empty array",
      "removed array element 1",
      "removed array element 2"
    )
  end

  it "ignores non-array nodes" do
    node = find_nodes(parse("value"), :send).first

    expect(described_class.new.mutate(node, subject: mutation_subject)).to eq([])
  end
end
