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

  it "declares the generic send node type" do
    expect(described_class.node_types).to eq([:send])
  end

  it "replaces generic method calls with nil" do
    mutant = mutate("service.call(1)", method_name: :call).first

    expect(mutant).to have_attributes(
      description: "replaced method call with nil",
      mutated_node: satisfy { |node| node.type == :nil }
    )
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
