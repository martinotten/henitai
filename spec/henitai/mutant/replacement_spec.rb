# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Mutant::Replacement do
  def render(original_source, mutated)
    original = Henitai::SourceParser.parse(original_source)
    mutant = Henitai::Mutant.new(subject: Henitai::Subject.new(namespace: "A", method_name: "b"), operator: "Fake",
                                 nodes: { original:, mutated: mutated || original }, description: "fake", location: {})
    described_class.render(mutant, original.location.expression)
  end

  it "parenthesises a logical operator" do
    expect(render("a && b", Henitai::SourceParser.parse("a || b"))).to eq("(a || b)")
  end

  it "parenthesises a binary operator call" do
    expect(render("x ** 2", Henitai::SourceParser.parse("x * 2"))).to eq("(x * 2)")
  end

  it "leaves other expressions bare" do
    expect(render("foo(1)", Henitai::SourceParser.parse("nil"))).to eq("nil")
  end

  it "keeps the original text for an unmutated control" do
    expect(render("a  &&  b", nil)).to eq("a  &&  b")
  end
end
