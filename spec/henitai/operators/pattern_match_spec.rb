# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::PatternMatch do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "pattern_match")
  end

  def mutate(source)
    node = find_nodes(parse(source), :case_match).first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the pattern match node type" do
    expect(described_class.node_types).to eq([:case_match])
  end

  it "removes individual in arms" do
    mutants = mutate(<<~RUBY)
      case value
      in { x: Integer } if ready
        :ok
      in { y: String }
        :other
      else
        :no
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "removed in arm 1",
      "removed pattern guard 1",
      "removed in arm 2"
    )
  end

  it "removes pattern guards from guarded arms" do
    mutant = mutate(<<~RUBY).find { |candidate| candidate.description == "removed pattern guard 1" }
      case value
      in { x: Integer } if ready
        :ok
      else
        :no
      end
    RUBY

    expect(mutant.mutated_node.children[1].children[1]).to be_nil
  end
end
