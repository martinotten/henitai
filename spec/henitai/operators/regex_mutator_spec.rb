# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::RegexMutator do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "validate")
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares regexp as its node type" do
    expect(described_class.node_types).to eq(%i[regexp])
  end

  it "swaps + quantifier to *" do
    node = find_nodes(parse("/foo+/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to include("replaced + quantifier with *")
  end

  it "swaps * quantifier to +" do
    node = find_nodes(parse("/foo*/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to include("replaced * quantifier with +")
  end

  it "removes a ^ start anchor" do
    node = find_nodes(parse("/^start/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to include("removed ^ anchor")
  end

  it "removes a $ end anchor" do
    node = find_nodes(parse("/end$/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to include("removed $ anchor")
  end

  it "negates a character class" do
    node = find_nodes(parse("/[a-z]/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to include("negated character class")
  end

  it "does not negate an already-negated character class" do
    node = find_nodes(parse("/[^a-z]/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).not_to include(a_string_matching(/negated character class/))
  end

  it "produces multiple mutations when several patterns apply" do
    node = find_nodes(parse("/^foo+/"), :regexp).first

    expect(mutate(node).length).to be > 1
  end

  it "does not emit a mutant when the replacement would be an invalid regex" do
    # Removing the only + from /+/ would produce //, which is valid, but
    # removing an anchor from something like /[/ would be invalid.
    # We test that no mutant is emitted when the result doesn't compile.
    # Use a regex where stripping yields invalid syntax: /[/ (unclosed class).
    # Since we can't produce that cleanly via source parse, we verify the
    # filter is in place by checking that every emitted mutant has a valid pattern.
    node = find_nodes(parse("/[a-z]+/"), :regexp).first
    mutants = mutate(node)

    mutants.each do |mutant|
      src = mutant.mutated_node.children[0].children[0]
      expect { Regexp.new(src) }.not_to raise_error
    end
  end

  it "treats anchors as one-way removals" do
    node = find_nodes(parse("/^foo$/"), :regexp).first
    descriptions = mutate(node).map(&:description)

    expect(descriptions).to contain_exactly("removed ^ anchor", "removed $ anchor")
  end

  it "does not mutate a regex with no applicable patterns" do
    node = find_nodes(parse("/simple/"), :regexp).first

    expect(mutate(node)).to eq([])
  end

  it "preserves regex flags in mutated nodes" do
    node = find_nodes(parse("/foo+/i"), :regexp).first
    mutant = mutate(node).find { |m| m.description.include?("+") }

    expect(mutant.mutated_node.children[1]).to eq(node.children[1])
  end

  it "skips duplicate regex mutants and invalid replacements" do
    node = find_nodes(parse("/simple/"), :regexp).first

    duplicate = described_class.new.send(
      :build_regex_mutant,
      node,
      nil,
      "simple",
      "simple",
      "noop",
      subject: mutation_subject
    )
    invalid = described_class.new.send(
      :build_regex_mutant,
      node,
      nil,
      "(",
      "simple",
      "broken",
      subject: mutation_subject
    )

    expect([duplicate, invalid]).to eq([nil, nil])
  end
end
