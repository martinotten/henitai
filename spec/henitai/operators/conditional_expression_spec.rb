# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::ConditionalExpression do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "conditional")
  end

  def find_nodes(node, type, results = [])
    return results unless node.respond_to?(:type)

    results << node if node.type == type
    node.children.each { |child| find_nodes(child, type, results) }
    results
  end

  def mutate(source)
    node = %i[if case while until].flat_map do |type|
      find_nodes(parse(source), type)
    end.first

    described_class.new.mutate(node, subject: mutation_subject)
  end

  it "declares the conditional node types" do
    expect(described_class.node_types).to eq(%i[if case while until])
  end

  it "mutates if expressions with then and else branches" do
    mutants = mutate(<<~RUBY)
      if ready
        :yes
      else
        :no
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced condition with true",
      "replaced condition with false",
      "negated condition",
      "removed else branch",
      "removed then branch"
    )
  end

  it "mutates if expressions without an else branch" do
    mutants = mutate(<<~RUBY)
      if ready
        :yes
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced condition with true",
      "replaced condition with false",
      "negated condition",
      "removed then branch"
    )
  end

  it "mutates modifier if, ternary, and unless forms" do
    aggregate_failures do
      modifier_if = mutate("value if ready")
      ternary = mutate("ready ? :yes : :no")
      modifier_unless = mutate("value unless ready")

      expect(modifier_if.map(&:description)).to contain_exactly(
        "replaced condition with true",
        "replaced condition with false",
        "negated condition",
        "removed then branch"
      )
      expect(ternary.map(&:description)).to contain_exactly(
        "replaced condition with true",
        "replaced condition with false",
        "negated condition",
        "removed else branch",
        "removed then branch"
      )
      expect(modifier_unless.map(&:description)).to contain_exactly(
        "replaced condition with true",
        "replaced condition with false",
        "negated condition"
      )
    end
  end

  it "mutates case expressions" do
    mutants = mutate(<<~RUBY)
      case state
      when :ready
        :go
      else
        :stop
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced condition with true",
      "replaced condition with false",
      "negated condition",
      "kept when branch",
      "kept else branch"
    )
  end

  it "mutates empty case expressions conservatively" do
    mutants = mutate(<<~RUBY)
      case state
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced condition with true",
      "replaced condition with false",
      "negated condition"
    )
  end

  it "mutates loop guards for while and until" do
    aggregate_failures do
      while_mutants = mutate(<<~RUBY)
        while running
          step
        end
      RUBY

      until_mutants = mutate(<<~RUBY)
        until ready
          step
        end
      RUBY

      expect(while_mutants.map(&:description)).to contain_exactly(
        "replaced condition with true",
        "replaced condition with false",
        "negated condition"
      )
      expect(until_mutants.map(&:description)).to contain_exactly(
        "replaced condition with true",
        "replaced condition with false",
        "negated condition"
      )
    end
  end

  it "ignores non-conditional nodes" do
    expect(described_class.new.mutate(parse("foo.bar"), subject: mutation_subject))
      .to eq([])
  end
end
