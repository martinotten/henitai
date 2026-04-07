# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::UnaryOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "compute")
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares send as its node type" do
    expect(described_class.node_types).to eq(%i[send])
  end

  it "removes unary minus" do
    node = find_nodes(parse("-x"), :send).find { |n| n.children[1] == :-@ }

    expect(mutate(node).first.description).to eq("removed unary -")
  end

  it "replaces unary minus node with its receiver" do
    node = find_nodes(parse("-x"), :send).find { |n| n.children[1] == :-@ }

    expect(mutate(node).first.mutated_node).to eq(node.children[0])
  end

  it "removes bitwise NOT" do
    node = find_nodes(parse("~flags"), :send).find { |n| n.children[1] == :~ }

    expect(mutate(node).first.description).to eq("removed unary ~")
  end

  it "does not mutate regular method calls" do
    node = find_nodes(parse("x.upcase"), :send).first

    expect(mutate(node)).to eq([])
  end

  it "does not mutate ! (owned by BooleanLiteral)" do
    node = find_nodes(parse("!enabled"), :send).find { |n| n.children[1] == :! }

    expect(mutate(node)).to eq([])
  end

  it "does not mutate arithmetic binary operators" do
    node = find_nodes(parse("a + b"), :send).first

    expect(mutate(node)).to eq([])
  end

  it "handles both unary operators in a single expression" do
    ast = parse("[-x, ~flags]")
    unary_nodes = find_nodes(ast, :send).select { |n| %i[-@ ~].include?(n.children[1]) }
    mutants = unary_nodes.flat_map { |n| mutate(n) }

    expect(mutants.map(&:description)).to contain_exactly(
      "removed unary -",
      "removed unary ~"
    )
  end
end
