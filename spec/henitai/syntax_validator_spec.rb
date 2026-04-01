# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SyntaxValidator do
  def mutant_for(mutated_node)
    subject = Henitai::Subject.new(
      namespace: "Sample",
      method_name: "alpha"
    )

    Henitai::Mutant.new(
      subject:,
      operator: "FakeOperator",
      nodes: {
        original: Parser::AST::Node.new(:int, [1]),
        mutated: mutated_node
      },
      description: "fake",
      location: {}
    )
  end

  it "accepts a mutant that unparse-compiles successfully" do
    mutant = mutant_for(Parser::AST::Node.new(:int, [2]))

    expect(described_class.new.valid?(mutant)).to be(true)
  end

  it "rejects a mutant whose mutated node cannot be unparsed" do
    mutant = mutant_for(Object.new)

    expect(described_class.new.valid?(mutant)).to be(false)
  end
end
