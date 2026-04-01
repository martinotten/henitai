# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::StringLiteral do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "render")
  end

  def find_nodes(node, type, results = [])
    return results unless node.respond_to?(:type)

    results << node if node.type == type
    node.children.each { |child| find_nodes(child, type, results) }
    results
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares string node types" do
    expect(described_class.node_types).to eq(%i[str dstr])
  end

  it "replaces plain strings with neutral alternatives" do
    mutants = mutate(find_nodes(parse("\"foo\""), :str).first)

    expect(mutants.map(&:description)).to contain_exactly(
      'replaced string with ""',
      'replaced string with "Henitai was here"'
    )
  end

  it "removes interpolation from heredocs" do
    aggregate_failures do
      node = find_nodes(parse(<<~RUBY), :dstr).first
        <<~TEXT
          hello \#{name}
        TEXT
      RUBY

      mutant = mutate(node).first

      expect(mutant.description).to eq("removed interpolation from string")
      expect(mutant.mutated_node.type).to eq(:str)
      expect(mutant.mutated_node.children.first).to include("hello")
    end
  end

  it "mutates strings inside percent-w arrays" do
    mutants = find_nodes(parse("%w[foo bar]"), :str).flat_map { |node| mutate(node) }

    expect(mutants.map(&:description).tally).to eq(
      'replaced string with ""' => 2,
      'replaced string with "Henitai was here"' => 2
    )
  end

  it "ignores non-string nodes" do
    expect(mutate(parse("foo.bar").children.first)).to eq([])
  end
end
