# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::UpdateOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "update")
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares op_asgn, or_asgn, and and_asgn as its node types" do
    expect(described_class.node_types).to eq(%i[op_asgn or_asgn and_asgn])
  end

  it "swaps += to -=" do
    node = find_nodes(parse("x += 1"), :op_asgn).first

    expect(mutate(node).first.description).to eq("replaced += with -=")
  end

  it "swaps -= to +=" do
    node = find_nodes(parse("x -= 1"), :op_asgn).first

    expect(mutate(node).first.description).to eq("replaced -= with +=")
  end

  it "swaps *= to /=" do
    node = find_nodes(parse("x *= 2"), :op_asgn).first

    expect(mutate(node).first.description).to eq("replaced *= with /=")
  end

  it "swaps /= to *=" do
    node = find_nodes(parse("x /= 2"), :op_asgn).first

    expect(mutate(node).first.description).to eq("replaced /= with *=")
  end

  it "swaps ||= to &&=" do
    node = find_nodes(parse("x ||= nil"), :or_asgn).first

    expect(mutate(node).first.description).to eq("replaced ||= with &&=")
  end

  it "swaps &&= to ||=" do
    node = find_nodes(parse("x &&= true"), :and_asgn).first

    expect(mutate(node).first.description).to eq("replaced &&= with ||=")
  end

  it "uses the swapped operator in the mutated node" do
    node = find_nodes(parse("total += amount"), :op_asgn).first

    expect(mutate(node).first.mutated_node.children[1]).to eq(:-)
  end

  it "preserves the assignment target in the mutated node" do
    node = find_nodes(parse("total += amount"), :op_asgn).first

    expect(mutate(node).first.mutated_node.children[0]).to eq(node.children[0])
  end

  it "does not mutate unrecognised compound operators" do
    node = find_nodes(parse("x **= 2"), :op_asgn).first

    expect(mutate(node)).to eq([])
  end
end
