# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::EqualityOperator do
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

  def identity_send_node(source)
    find_nodes(parse(source), :send).find { |node| %i[eql? equal?].include?(node.children[1]) }
  end

  def mutate(source)
    described_class.new.mutate(comparison_node(source), subject: mutation_subject)
  end

  it "declares comparison send nodes" do
    expect(described_class.node_types).to eq([:send])
  end

  it "replaces each relational operator with the other relational operators" do
    aggregate_failures do
      mutants = mutate("left == right")

      expect(mutants).to have_attributes(size: 6)
      expect(mutants.map(&:description)).to contain_exactly(
        "replaced == with !=",
        "replaced == with <",
        "replaced == with >",
        "replaced == with <=",
        "replaced == with >=",
        "replaced == with <=>"
      )
    end
  end

  it "ignores identity-method sends, handled by EqualityIdentityOperator" do
    aggregate_failures do
      expect(described_class.new.mutate(identity_send_node("left.eql?(right)"), subject: mutation_subject))
        .to eq([])
      expect(described_class.new.mutate(identity_send_node("left.equal?(right)"), subject: mutation_subject))
        .to eq([])
    end
  end

  it "mutates comparisons in conditionals, guard clauses, and Comparable methods" do
    aggregate_failures do
      conditional = mutate(<<~RUBY)
        if value == expected
          :ok
        end
      RUBY

      guard_clause = mutate(<<~RUBY)
        raise "bad" unless value != nil
      RUBY

      comparable = mutate(<<~RUBY)
        def <=>(other)
          value <=> other.value
        end
      RUBY

      expect(conditional.map(&:description)).to include("replaced == with !=")
      expect(guard_clause.map(&:description)).to include("replaced != with ==")
      expect(comparable.map(&:description)).to include("replaced <=> with ==")
    end
  end

  it "ignores non-comparison sends" do
    expect(described_class.new.mutate(parse("foo.bar"), subject: mutation_subject))
      .to eq([])
  end

  it "preserves the receiver and right operand exactly, only swapping the selector" do
    node = comparison_node("left == right")
    mutants = mutate("left == right")

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
