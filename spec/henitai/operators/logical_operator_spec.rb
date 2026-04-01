# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::LogicalOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "predicate")
  end

  def mutate(source)
    node = find_nodes(parse(source), :and).first || find_nodes(parse(source), :or).first
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares and and or node types" do
    expect(described_class.node_types).to eq(%i[and or])
  end

  it "mutates && to ||, lhs, and rhs" do
    aggregate_failures do
      mutants = mutate("left && right")

      expect(mutants.map(&:description)).to contain_exactly(
        "replaced && with ||",
        "replaced && with lhs",
        "replaced && with rhs"
      )
      expect(mutants.map { |mutant| mutant.mutated_node.type }).to contain_exactly(
        :or,
        :send,
        :send
      )
    end
  end

  it "mutates || to &&, lhs, and rhs" do
    aggregate_failures do
      mutants = mutate("left || right")

      expect(mutants.map(&:description)).to contain_exactly(
        "replaced || with &&",
        "replaced || with lhs",
        "replaced || with rhs"
      )
      expect(mutants.map { |mutant| mutant.mutated_node.type }).to contain_exactly(
        :and,
        :send,
        :send
      )
    end
  end

  it "mutates keyword and/or forms the same way" do
    aggregate_failures do
      expect(mutate("left and right").map(&:description)).to contain_exactly(
        "replaced && with ||",
        "replaced && with lhs",
        "replaced && with rhs"
      )

      expect(mutate("left or right").map(&:description)).to contain_exactly(
        "replaced || with &&",
        "replaced || with lhs",
        "replaced || with rhs"
      )
    end
  end

  it "ignores non-logical nodes" do
    expect(described_class.new.mutate(parse("foo.bar"), subject: mutation_subject))
      .to eq([])
  end
end
