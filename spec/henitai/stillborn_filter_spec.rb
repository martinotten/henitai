# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::StillbornFilter do
  def build_mutant(source)
    node = Henitai::SourceParser.parse(source)

    Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "example mutation",
      location: {
        file: "(string)",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )
  end

  it "keeps syntactically valid mutants" do
    mutant = build_mutant("1")

    expect(described_class.new.suppressed?(mutant)).to be(false)
  end

  it "suppresses mutants that unparse to invalid Ruby" do
    mutant = build_mutant("1")

    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_return("def")

    expect(described_class.new.suppressed?(mutant)).to be(true)
  end

  it "suppresses mutants when unparsing raises" do
    mutant = build_mutant("1")

    allow(Unparser).to receive(:unparse).with(mutant.mutated_node).and_raise(StandardError, "boom")

    expect(described_class.new.suppressed?(mutant)).to be(true)
  end

  it "does not flag return mutants as stillborn" do
    mutant = build_mutant("return 1")

    expect(described_class.new.suppressed?(mutant)).to be(false)
  end
end
