# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::EqualityIdentityOperator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "compare")
  end

  def comparison_node(source)
    find_nodes(parse(source), :send).find do |node|
      described_class::OPERATORS.include?(node.children[1])
    end
  end

  def mutate(source)
    described_class.new.mutate(comparison_node(source), subject: mutation_subject)
  end

  it "declares comparison send nodes" do
    expect(described_class.node_types).to eq([:send])
  end

  it "replaces a relational operator only with the identity methods" do
    mutants = mutate("left == right")

    aggregate_failures do
      expect(mutants).to have_attributes(size: 2)
      expect(mutants.map(&:description)).to contain_exactly(
        "replaced == with eql?",
        "replaced == with equal?"
      )
    end
  end

  it "replaces an identity method with every other operator" do
    mutants = mutate("left.eql?(right)")

    aggregate_failures do
      expect(mutants).to have_attributes(size: 8)
      expect(mutants.map(&:description)).to contain_exactly(
        "replaced eql? with ==",
        "replaced eql? with !=",
        "replaced eql? with <",
        "replaced eql? with >",
        "replaced eql? with <=",
        "replaced eql? with >=",
        "replaced eql? with <=>",
        "replaced eql? with equal?"
      )
    end
  end

  it "ignores non-comparison sends" do
    expect(described_class.new.mutate(parse("foo.bar"), subject: mutation_subject))
      .to eq([])
  end

  it "preserves the receiver and right operand exactly, only swapping the selector" do
    node = comparison_node("left.equal?(right)")
    mutants = mutate("left.equal?(right)")

    aggregate_failures do
      mutants.each do |mutant|
        expect(mutant.mutated_node).to be_a(Parser::AST::Node)
        expect(mutant.mutated_node.type).to eq(:send)
        expect(mutant.mutated_node.children.size).to eq(node.children.size)
        expect(mutant.mutated_node.children[0]).to eq(node.children[0])
        expect(mutant.mutated_node.children[2]).to eq(node.children[2])
      end
    end
  end
end
