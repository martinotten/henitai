# frozen_string_literal: true

require "spec_helper"
require "unparser"

RSpec.describe Henitai::Operators::ConditionalExpression do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def mutation_subject
    Henitai::Subject.new(namespace: "Example", method_name: "conditional")
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
      "kept when branch 1",
      "kept else branch"
    )
  end

  it "mutates case expressions with multiple when branches" do
    mutants = mutate(<<~RUBY)
      case state
      when :ready
        :go
      when :waiting
        :hold
      else
        :stop
      end
    RUBY

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced condition with true",
      "replaced condition with false",
      "negated condition",
      "kept when branch 1",
      "kept when branch 2",
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

  it "produces parseable mutated nodes for all if-expression variants" do
    # Use an if without else so that "removed then branch" exercises nil_node
    # (else_branch is nil, so the replacement falls to nil_node).
    mutants = mutate(<<~RUBY)
      if ready
        :yes
      end
    RUBY

    aggregate_failures do
      mutants.each do |mutant|
        msg = "#{mutant.description} produced an unparseable node: " \
              "#{mutant.mutated_node.inspect}"
        expect { Unparser.unparse(mutant.mutated_node) }.not_to raise_error, msg
      end
    end
  end
end
