# frozen_string_literal: true

require "spec_helper"
require "unparser"

RSpec.describe Henitai::SourceParser do
  def collect_node_types(node)
    types = []
    queue = [node]

    until queue.empty?
      current = queue.shift
      types << current.type if current.respond_to?(:type)
      queue.concat(current.children.compact) if current.respond_to?(:children)
    end

    types.uniq
  end

  def mutation_surface_source
    <<~RUBY
      class Sample
        def answer = 1 + 2
      end

      values = [1, 2, 3]
      thresholds = { low: 1 }
      range = 1..3
      user = profile&.user
      total += 1 if enabled && active
      case payload
      in { answer: } then answer
      end
    RUBY
  end

  def expected_mutation_surface_types
    %i[
      class
      def
      send
      and
      csend
      array
      hash
      irange
      op_asgn
      case_match
      in_pattern
    ]
  end

  it "preserves the source path in AST locations" do
    ast = described_class.parse(
      "class Sample; def answer = 1 + 2; end",
      path: "sample.rb"
    )

    expect(ast.location.expression.source_buffer.name).to eq("sample.rb")
  end

  it "exposes the node types needed for mutation operators" do
    ast = described_class.parse(mutation_surface_source, path: "sample.rb")

    expect(collect_node_types(ast)).to include(*expected_mutation_surface_types)
  end

  it "can be unparsed back to source" do
    ast = described_class.parse(
      "class Sample; def answer = 1 + 2; end",
      path: "sample.rb"
    )

    expect(Unparser.unparse(ast)).to eq(<<~RUBY)
      class Sample
        def answer
          1 + 2
        end
      end
    RUBY
  end
end
