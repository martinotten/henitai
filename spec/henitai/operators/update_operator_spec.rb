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

  it "preserves the target and value when swapping logical assignments" do
    aggregate_failures do
      or_node = find_nodes(parse("x ||= nil"), :or_asgn).first
      and_node = find_nodes(parse("x &&= true"), :and_asgn).first

      or_mutant = mutate(or_node).first
      and_mutant = mutate(and_node).first

      expect(or_mutant.mutated_node.children[0]).to eq(or_node.children[0])
      expect(or_mutant.mutated_node.children[1]).to eq(or_node.children[1])
      expect(and_mutant.mutated_node.children[0]).to eq(and_node.children[0])
      expect(and_mutant.mutated_node.children[1]).to eq(and_node.children[1])
    end
  end

  it "uses the swapped operator in the mutated node" do
    node = find_nodes(parse("total += amount"), :op_asgn).first

    expect(mutate(node).first.mutated_node.children[1]).to eq(:-)
  end

  it "preserves the assignment target in the mutated node" do
    node = find_nodes(parse("total += amount"), :op_asgn).first

    expect(mutate(node).first.mutated_node.children[0]).to eq(node.children[0])
  end

  it "does not mutate unsupported compound operators" do
    exponent = find_nodes(parse("x **= 2"), :op_asgn).first
    modulo = find_nodes(parse("x %= 2"), :op_asgn).first

    expect([mutate(exponent), mutate(modulo)]).to eq([[], []])
  end
end
