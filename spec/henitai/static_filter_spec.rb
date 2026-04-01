# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::StaticFilter do
  def build_mutant(source)
    node = Henitai::SourceParser.parse(source)

    Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: { original: node, mutated: node },
      description: "example mutation",
      location: {
        file: "sample.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )
  end

  def config(ignore_patterns: [])
    Struct.new(:ignore_patterns).new(ignore_patterns)
  end

  it "marks mutants whose source matches an ignore pattern as ignored" do
    mutant = build_mutant("foo.bar")

    described_class.new.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(mutant.status).to eq(:ignored)
  end

  it "caches compiled ignore patterns across repeated applications" do
    mutant = build_mutant("foo.bar")
    filter = described_class.new

    allow(Regexp).to receive(:new).and_call_original

    filter.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))
    filter.apply([mutant], config(ignore_patterns: ["foo\\.bar"]))

    expect(Regexp).to have_received(:new).once
  end

  it "keeps mutants that do not match any ignore pattern pending" do
    mutant = build_mutant("foo.bar")

    described_class.new.apply([mutant], config(ignore_patterns: ["foo\\.baz"]))

    expect(mutant.status).to eq(:pending)
  end

  it "treats a nil config as having no ignore patterns" do
    mutant = build_mutant("foo.bar")

    described_class.new.apply([mutant], nil)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps mutants without source metadata pending" do
    mutant = Henitai::Mutant.new(
      subject: Henitai::Subject.new(namespace: "Example", method_name: "example"),
      operator: "ArithmeticOperator",
      nodes: {
        original: Struct.new(:location).new(Struct.new(:expression).new(nil)),
        mutated: Struct.new(:location).new(Struct.new(:expression).new(nil))
      },
      description: "example mutation",
      location: {
        file: "sample.rb",
        start_line: 1,
        end_line: 1,
        start_col: 0,
        end_col: 1
      }
    )

    described_class.new.apply([mutant], config(ignore_patterns: ["foo"]))

    expect(mutant.status).to eq(:pending)
  end
end
