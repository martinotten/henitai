# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SamplingStrategy do
  def mutant(subject_expression, description, start_line)
    subject = Henitai::Subject.new(expression: subject_expression)

    Henitai::Mutant.new(
      subject:,
      operator: "FakeOperator",
      nodes: {
        original: Parser::AST::Node.new(:int, [1]),
        mutated: Parser::AST::Node.new(:int, [2])
      },
      description:,
      location: mutant_location(start_line)
    )
  end

  def mutant_location(start_line)
    {
      file: "sample.rb",
      start_line:,
      end_line: start_line,
      start_col: 0,
      end_col: 1
    }
  end

  it "samples per subject instead of globally" do
    mutants = [
      mutant("Sample#alpha", "alpha-1", 1),
      mutant("Sample#alpha", "alpha-2", 2),
      mutant("Sample#alpha", "alpha-3", 3),
      mutant("Sample#beta", "beta-1", 4)
    ]

    sampled = described_class.new.sample(mutants, ratio: 0.25)

    expect(sampled.map(&:description)).to eq(%w[alpha-1 beta-1])
  end

  it "returns no mutants when the ratio is zero" do
    mutants = [mutant("Sample#alpha", "alpha-1", 1)]

    expect(described_class.new.sample(mutants, ratio: 0.0)).to eq([])
  end

  it "returns multiple samples per subject when the ratio warrants it" do
    mutants = [
      mutant("Sample#alpha", "a-1", 1),
      mutant("Sample#alpha", "a-2", 2),
      mutant("Sample#alpha", "a-3", 3),
      mutant("Sample#alpha", "a-4", 4)
    ]

    expect(described_class.new.sample(mutants, ratio: 0.5).size).to eq(2)
  end

  it "rejects unsupported sampling strategies" do
    mutants = [mutant("Sample#alpha", "alpha-1", 1)]

    expect do
      described_class.new.sample(mutants, ratio: 0.5, strategy: :random)
    end.to raise_error(ArgumentError, /Unsupported sampling strategy/)
  end
end
