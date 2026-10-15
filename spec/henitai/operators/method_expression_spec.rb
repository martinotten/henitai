# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::MethodExpression do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "method_expression")
  end

  def mutate(source, method_name:)
    node = find_nodes(parse(source), :send).find do |candidate|
      candidate.children[1] == method_name
    end

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the send and block node types" do
    expect(described_class.node_types).to eq(%i[send block numblock])
  end

  it "replaces generic method calls with nil" do
    mutant = mutate("service.call(1)", method_name: :call).first

    expect(mutant).to have_attributes(
      description: "replaced method call with nil",
      mutated_node: satisfy { |node| node.type == :nil }
    )
  end

  it "replaces a call with its block as a whole" do
    node = parse("items.map { |item| item * 2 }")

    mutant = described_class.new.mutate(node, subject: mutation_subject).first

    expect([mutant.original_node, mutant.mutated_node.type]).to eq([node, :nil])
  end

  it "replaces a call with a numbered-parameter block as a whole" do
    node = parse("items.map { _1 * 2 }")

    expect(described_class.new.mutate(node, subject: mutation_subject).map(&:original_node)).to eq([node])
  end

  it "ignores lambda literals" do
    expect(described_class.new.mutate(parse("-> { work }"), subject: mutation_subject)).to eq([])
  end

  it "ignores non-send nodes" do
    expect(described_class.new.mutate(parse("123"), subject: mutation_subject)).to eq([])
  end

  it "ignores arithmetic operator sends" do
    expect(mutate("a + b", method_name: :+)).to eq([])
  end

  it "ignores setter-style sends" do
    expect(mutate("service.value = input", method_name: :value=)).to eq([])
  end

  it "ignores unary negation sends" do
    expect(mutate("!value", method_name: :!)).to eq([])
  end
end
