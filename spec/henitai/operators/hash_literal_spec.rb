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

  it "mutates symbol keys to string keys" do
    mutant = mutate("{ foo: 1 }").last

    expect(mutant).to have_attributes(
      description: "replaced symbol key with string key",
      mutated_node: satisfy { |node| node.children.first.children.first.type == :str }
    )
  end

  it "mutates each symbol key independently" do
    mutants = mutate("{ foo: 1, bar: 2 }")

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "replaced symbol key with string key",
        "replaced symbol key with string key"
      ]
    )
  end

  it "mutates only symbol-keyed pairs in mixed hashes" do
    mutants = mutate('{ foo: 1, "bar" => 2 }')

    expect(mutants.map(&:description)).to eq(
      [
        "replaced hash with empty hash",
        "replaced symbol key with string key"
      ]
    )
  end

  it "does not treat string-keyed pairs as symbol keys" do
    expect(mutate('{ "bar" => 2 }').map(&:description)).to eq(
      ["replaced hash with empty hash"]
    )
  end

  it "ignores empty hashes" do
    expect(mutate("{}")).to eq([])
  end
end
