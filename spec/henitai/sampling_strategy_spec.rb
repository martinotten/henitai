# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SamplingStrategy do
  def mutant(subject_expression, description, start_line, operator: "FakeOperator")
    subject = Henitai::Subject.new(expression: subject_expression)

    Henitai::Mutant.new(
      subject:,
      operator:,
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

  def descriptions(mutants) = mutants.map(&:description)

  def sample_descriptions(mutants, ratio:, seed: described_class::DEFAULT_SEED)
    descriptions(described_class.new.sample(mutants, ratio:, seed:))
  end

  describe "per-subject sample size" do
    it "samples per subject instead of globally" do
      mutants = [
        mutant("Sample#alpha", "alpha-1", 1),
        mutant("Sample#alpha", "alpha-2", 2),
        mutant("Sample#alpha", "alpha-3", 3),
        mutant("Sample#beta", "beta-1", 4)
      ]

      sampled = described_class.new.sample(mutants, ratio: 0.25)

      expect(sampled.count { |item| item.subject.expression == "Sample#alpha" }).to eq(1)
    end

    it "keeps at least one mutant per subject even for a tiny ratio" do
      mutants = [mutant("Sample#beta", "beta-1", 4)]

      expect(sample_descriptions(mutants, ratio: 0.01)).to eq(%w[beta-1])
    end

    it "keeps every mutant when the ratio would exceed the subject size" do
      mutants = [mutant("Sample#alpha", "a-1", 1), mutant("Sample#alpha", "a-2", 2)]

      expect(sample_descriptions(mutants, ratio: 5.0).sort).to eq(%w[a-1 a-2])
    end

    it "returns multiple samples per subject when the ratio warrants it" do
      mutants = Array.new(4) { |index| mutant("Sample#alpha", "a-#{index}", index + 1) }

      expect(described_class.new.sample(mutants, ratio: 0.5).size).to eq(2)
    end

    it "does not let one subject's mutants change another subject's sample" do
      alpha = [mutant("Sample#alpha", "a-1", 1), mutant("Sample#alpha", "a-2", 2)]
      beta = [mutant("Sample#beta", "b-1", 3), mutant("Sample#beta", "b-2", 4)]

      alone = sample_descriptions(alpha, ratio: 0.5)
      with_others = sample_descriptions(alpha + beta, ratio: 0.5).select { |item| item.start_with?("a-") }

      expect(with_others).to eq(alone)
    end
  end

  describe "stratification by operator" do
    it "represents every operator stratum when the sample size covers all strata" do
      mutants = %w[arithmetic equality boolean].flat_map do |operator|
        Array.new(10) { |index| mutant("Sample#alpha", "#{operator}-#{index}", index + 1, operator:) }
      end

      operators = described_class.new.sample(mutants, ratio: 0.1).map { |item| item.operator.to_s }

      expect(operators.sort).to eq(%w[arithmetic boolean equality])
    end

    it "does not simply take the first N mutants in walk order" do
      mutants = [
        mutant("Sample#alpha", "a-1", 1, operator: "arithmetic"),
        mutant("Sample#alpha", "a-2", 2, operator: "arithmetic"),
        mutant("Sample#alpha", "a-3", 3, operator: "arithmetic"),
        mutant("Sample#alpha", "b-1", 4, operator: "boolean")
      ]

      expect(sample_descriptions(mutants, ratio: 0.5)).to include("b-1")
    end
  end

  describe "determinism" do
    it "returns the same sample for the same input and seed" do
      mutants = Array.new(12) { |index| mutant("Sample#alpha", "a-#{index}", index + 1) }

      first = sample_descriptions(mutants, ratio: 0.5, seed: 7)
      second = sample_descriptions(mutants, ratio: 0.5, seed: 7)

      expect(first).to eq(second)
    end

    it "uses the default seed when none is given" do
      mutants = Array.new(12) { |index| mutant("Sample#alpha", "a-#{index}", index + 1) }

      expect(described_class.new.sample(mutants, ratio: 0.5))
        .to eq(described_class.new.sample(mutants, ratio: 0.5, seed: described_class::DEFAULT_SEED))
    end

    it "changes the selected mutants when the seed changes" do
      mutants = Array.new(12) { |index| mutant("Sample#alpha", "a-#{index}", index + 1) }

      samples = (0..4).map { |seed| sample_descriptions(mutants, ratio: 0.25, seed:).sort }

      expect(samples.uniq.size).to be > 1
    end
  end

  describe "output order" do
    it "returns the kept mutants in their original input order" do
      mutants = Array.new(8) do |index|
        mutant("Sample#alpha", "a-#{index}", index + 1, operator: "op-#{index % 3}")
      end

      sampled = sample_descriptions(mutants, ratio: 0.5)

      expect(sampled).to eq(descriptions(mutants).select { |description| sampled.include?(description) })
    end
  end

  it "returns no mutants when the ratio is zero" do
    mutants = [mutant("Sample#alpha", "alpha-1", 1)]

    expect(described_class.new.sample(mutants, ratio: 0.0)).to eq([])
  end

  it "rejects unsupported sampling strategies" do
    mutants = [mutant("Sample#alpha", "alpha-1", 1)]
    unsupported_strategy = Class.new do
      def to_s = "custom-strategy"
    end.new

    expect do
      described_class.new.sample(mutants, ratio: 0.5, strategy: unsupported_strategy)
    end.to raise_error(ArgumentError, "Unsupported sampling strategy: custom-strategy")
  end

  it "accepts a string strategy name" do
    mutants = [
      mutant("Sample#alpha", "alpha-1", 1),
      mutant("Sample#alpha", "alpha-2", 2)
    ]

    sampled = described_class.new.sample(mutants, ratio: 0.5, strategy: "stratified")

    expect(sampled.size).to eq(1)
  end
end
