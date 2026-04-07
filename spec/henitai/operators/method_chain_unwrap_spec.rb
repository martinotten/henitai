# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::MethodChainUnwrap do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "process")
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares send as its node type" do
    expect(described_class.node_types).to eq(%i[send])
  end

  it "removes the outermost link in a simple chain" do
    outer = find_nodes(parse("array.uniq.sort.first"), :send).find { |n| n.children[1] == :first }

    expect(mutate(outer).first.description).to eq("removed .first from chain")
  end

  it "replaces the outer node with its receiver" do
    outer = find_nodes(parse("array.uniq.sort.first"), :send).find { |n| n.children[1] == :first }

    expect(mutate(outer).first.mutated_node).to eq(outer.children[0])
  end

  it "removes intermediate chain links" do
    # array.uniq.sort — .sort has a :send receiver (:uniq)
    outer = find_nodes(parse("array.uniq.sort"), :send).find do |n|
      n.children[1] == :sort
    end

    mutant = mutate(outer).first

    expect(mutant.description).to eq("removed .sort from chain")
  end

  it "does not fire on the chain root (nil receiver)" do
    # s(:send, nil, :array) — receiver is Ruby nil, not a node
    root = find_nodes(parse("array.uniq"), :send).find { |n| n.children[0].nil? }

    expect(mutate(root)).to eq([])
  end

  it "does not fire when the receiver is a block node" do
    # list.select { }.count — .count has a :block receiver
    outer = find_nodes(parse("list.select { }.count"), :send).find do |n|
      n.children[1] == :count
    end

    expect(mutate(outer)).to eq([])
  end

  it "does not fire on non-chained standalone calls" do
    node = find_nodes(parse("puts 'hello'"), :send).first

    expect(mutate(node)).to eq([])
  end

  it "produces a mutant for each chainable send node in a longer chain" do
    ast = parse("array.uniq.sort.first")
    chainable = find_nodes(ast, :send).select do |n|
      n.children[0].is_a?(Parser::AST::Node) && n.children[0].type == :send
    end

    mutants = chainable.flat_map { |n| mutate(n) }

    expect(mutants.map(&:description)).to contain_exactly(
      "removed .uniq from chain",
      "removed .sort from chain",
      "removed .first from chain"
    )
  end
end
