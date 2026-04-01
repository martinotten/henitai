# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::BlockStatement do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "block")
  end

  def mutate(source)
    node = find_nodes(parse(source), :block).first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the block node type" do
    expect(described_class.node_types).to eq([:block])
  end

  it "removes block bodies" do
    mutant = mutate("foo { bar }").first

    expect(mutant).to have_attributes(
      description: "removed block content",
      mutated_node: satisfy { |node| node.children.last.nil? }
    )
  end

  it "preserves block arguments while removing the body" do
    mutant = mutate("foo { |x| x * 2 }").first

    expect(mutant.mutated_node.children[1].children.first.type).to eq(:arg)
  end

  it "ignores empty blocks" do
    expect(mutate("foo {}")).to eq([])
  end
end
