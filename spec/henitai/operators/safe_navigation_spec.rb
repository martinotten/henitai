# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::SafeNavigation do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "safe_navigation")
  end

  def mutate(source)
    node = find_nodes(parse(source), :csend).first

    described_class.new.mutate(node, subject: mutation_subject).first
  end

  it "declares the safe navigation node type" do
    expect(described_class.node_types).to eq([:csend])
  end

  it "removes nil guards from safe navigation calls" do
    mutant = mutate("user&.name")

    expect(mutant).to have_attributes(
      description: "removed nil guard",
      mutated_node: satisfy { |node| node.type == :send }
    )
  end

  it "preserves safe navigation arguments when removing the guard" do
    mutant = mutate("user&.name(1)")

    expect(mutant.mutated_node.children[2].type).to eq(:int)
  end
end
