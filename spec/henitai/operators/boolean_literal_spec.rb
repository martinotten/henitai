# frozen_string_literal: true

require "spec_helper"

# rubocop:disable Lint/BooleanSymbol
RSpec.describe Henitai::Operators::BooleanLiteral do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "feature_flag")
  end

  def mutate(node)
    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares true, false, and send node types" do
    expect(described_class.node_types).to eq(%i[true false send])
  end

  it "toggles true and false literals" do
    aggregate_failures do
      expect(mutate(find_nodes(parse("true"), :true).first).first.description)
        .to eq("replaced true with false")
      expect(mutate(find_nodes(parse("false"), :false).first).first.description)
        .to eq("replaced false with true")
    end
  end

  it "removes unary negation" do
    aggregate_failures do
      node = find_nodes(parse("!enabled"), :send).find do |candidate|
        candidate.children[1] == :!
      end

      mutant = mutate(node).first

      expect(mutant.description).to eq("removed negation")
      expect(mutant.mutated_node.type).to eq(:send)
    end
  end

  it "handles booleans in defaults, hashes, and ternaries" do
    source = <<~RUBY
      def example(enabled = true)
        {
          active: false,
          inverted: !enabled,
          branch: enabled ? true : false
        }
      end
    RUBY

    ast = parse(source)
    nodes = find_nodes(ast, :true) + find_nodes(ast, :false) +
            find_nodes(ast, :send).select { |node| node.children[1] == :! }
    mutants = nodes.flat_map { |node| mutate(node) }

    expect(mutants.map(&:description).tally).to eq(
      "replaced true with false" => 2,
      "replaced false with true" => 2,
      "removed negation" => 1
    )
  end

  it "ignores non-boolean nodes" do
    expect(mutate(parse("if enabled\n  :yes\nend").children.first)).to eq([])
  end

  it "ignores malformed negation nodes without a receiver" do
    node = Struct.new(:type, :children).new(:send, [nil, :!])

    expect(mutate(node)).to eq([])
  end
end
# rubocop:enable Lint/BooleanSymbol
