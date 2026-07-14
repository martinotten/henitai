# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::HashKeyType do
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

  it "mutates symbol keys to string keys" do
    mutant = mutate("{ foo: 1 }").first

    expect(mutant).to have_attributes(
      description: "replaced symbol key with string key",
      mutated_node: satisfy { |node| node.children.first.children.first.type == :str }
    )
  end

  it "mutates each symbol key independently" do
    expect(mutate("{ foo: 1, bar: 2 }").map(&:description)).to eq(
      [
        "replaced symbol key with string key",
        "replaced symbol key with string key"
      ]
    )
  end

  it "changes only one symbol key in each mutant" do
    key_types = mutate("{ foo: 1, bar: 2 }").map do |mutant|
      mutant.mutated_node.children.map { |pair| pair.children.first.type }
    end

    expect(key_types).to contain_exactly(%i[str sym], %i[sym str])
  end

  it "mutates only symbol-keyed pairs in mixed hashes" do
    expect(mutate('{ foo: 1, "bar" => 2 }').map(&:description)).to eq(
      ["replaced symbol key with string key"]
    )
  end

  it "does not treat string-keyed pairs as symbol keys" do
    expect(mutate('{ "bar" => 2 }')).to eq([])
  end

  it "ignores empty hashes" do
    expect(mutate("{}")).to eq([])
  end
end
