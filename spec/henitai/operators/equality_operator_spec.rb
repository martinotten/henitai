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

  def mutate(source)
    described_class.new.mutate(comparison_node(source), subject: mutation_subject)
  end

  it "declares comparison send nodes" do
    expect(described_class.node_types).to eq([:send])
  end

  it "replaces each comparison operator with the other operators" do
    aggregate_failures do
      mutants = mutate("left == right")

      expect(mutants).to have_attributes(size: 8)
      expect(mutants.map(&:description)).to contain_exactly(
        "replaced == with !=",
        "replaced == with <",
        "replaced == with >",
        "replaced == with <=",
        "replaced == with >=",
        "replaced == with <=>",
        "replaced == with eql?",
        "replaced == with equal?"
      )
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

  it "preserves the right operand in each mutated send node" do
    mutant = mutate("left == right").first
    expect(mutant.mutated_node.children[2]).not_to be_nil
  end

  it "produces a :send AST node for each replacement" do
    mutants = mutate("left == right")
    aggregate_failures do
      mutants.each do |mutant|
        expect(mutant.mutated_node).to be_a(Parser::AST::Node)
        expect(mutant.mutated_node.type).to eq(:send)
      end
    end
  end
end
