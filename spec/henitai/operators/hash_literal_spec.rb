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

  it "removes string-keyed pairs too" do
    mutants = mutate('{ foo: 1, "bar" => 2 }')

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "removed hash pair foo",
        "removed hash pair bar"
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
