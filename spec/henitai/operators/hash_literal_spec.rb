# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::HashLiteral do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "hash")
  end

  def mutate(source)
    node = find_nodes(parse(source), :hash).first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the hash node type" do
    expect(described_class.node_types).to eq([:hash])
  end

  it "replaces non-empty hashes with empty hashes" do
    mutant = mutate("{ foo: 1 }").first

    expect(mutant).to have_attributes(
      description: "replaced hash with empty hash",
      mutated_node: satisfy { |node| node.type == :hash && node.children.empty? }
    )
  end

  # Descriptions reach the terminal summary, the JSON report, and
  # MutantIdentity.stable_id, so a non-literal key must never leak an AST
  # s-expression (or its newlines) into them.
  describe "pair labels for non-literal keys" do
    def pair_removal_descriptions(source)
      mutate(source).map(&:description).drop(1)
    end

    it "labels variable keys by position rather than emitting a blank label" do
      expect(pair_removal_descriptions("{ foo => 1, bar => 2 }")).to eq(
        ["removed hash pair #1", "removed hash pair #2"]
      )
    end

    it "labels an array key by position rather than leaking an s-expression" do
      expect(pair_removal_descriptions("{ [1] => 2, x: 3 }")).to eq(
        ["removed hash pair #1", "removed hash pair x"]
      )
    end

    it "labels a nested-hash key by position rather than emitting a multi-line description" do
      expect(pair_removal_descriptions("{ { a: 1 } => 2, x: 3 }")).to eq(
        ["removed hash pair #1", "removed hash pair x"]
      )
    end

    it "labels an interpolated symbol key by position rather than naming one fragment" do
      interpolated_key_hash = <<~'RUBY'.strip
        { "a#{x}": 1, y: 2 }
      RUBY

      expect(pair_removal_descriptions(interpolated_key_hash)).to eq(
        ["removed hash pair #1", "removed hash pair y"]
      )
    end

    it "labels a symbol key containing a newline by position" do
      newline_key_hash = <<~'RUBY'.strip
        { :"a\nb" => 1, x: 2 }
      RUBY

      expect(pair_removal_descriptions(newline_key_hash)).to eq(
        ["removed hash pair #1", "removed hash pair x"]
      )
    end

    it "keeps every description single-line" do
      descriptions = pair_removal_descriptions("{ { a: 1 } => 2, [1] => 3, x: 4 }")

      expect(descriptions.grep(/\n/)).to be_empty
    end

    it "distinguishes a string key from the same-named symbol key" do
      expect(pair_removal_descriptions('{ "a" => 1, a: 2 }')).to eq(
        ['removed hash pair "a"', "removed hash pair a"]
      )
    end

    it "labels keyword literal keys by their keyword" do
      expect(pair_removal_descriptions("{ nil => 1, true => 2, 3 => 4 }")).to eq(
        ["removed hash pair nil", "removed hash pair true", "removed hash pair 3"]
      )
    end
  end

  it "removes each pair independently" do
    mutants = mutate("{ foo: 1, bar: 2 }")

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "removed hash pair foo",
        "removed hash pair bar"
      ]
    )
  end

  it "keeps the other pairs intact in each removal mutant" do
    removal_mutants = mutate("{ foo: 1, bar: 2 }").drop(1)

    removed_to_remaining = removal_mutants.to_h do |mutant|
      remaining = mutant.mutated_node.children.map { |pair| pair.children.first.children.first }
      [mutant.description, remaining]
    end

    expect(removed_to_remaining).to eq(
      "removed hash pair foo" => [:bar],
      "removed hash pair bar" => [:foo]
    )
  end

  it "removes string-keyed pairs too, labelling them quoted" do
    mutants = mutate('{ foo: 1, "bar" => 2 }')

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "removed hash pair foo",
        'removed hash pair "bar"'
      ]
    )
  end

  it "skips pair removal for single-pair hashes (duplicate of the empty-hash mutant)" do
    expect(mutate("{ foo: 1 }").map(&:description)).to eq(
      ["replaced hash with empty hash"]
    )
  end

  it "does not emit symbol-key type mutations" do
    descriptions = mutate("{ foo: 1, bar: 2 }").map(&:description)

    expect(descriptions.grep(/string key/)).to be_empty
  end

  it "ignores empty hashes" do
    expect(mutate("{}")).to eq([])
  end

  it "skips double-splat entries when removing pairs" do
    mutants = mutate("{ foo: 1, **rest }")

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "removed hash pair foo"
      ]
    )
  end
end
