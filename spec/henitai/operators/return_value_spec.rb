# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Operators::ReturnValue do
  def parse(source)
    Henitai::SourceParser.parse(source)
  end

  def method_subject(source)
    Henitai::Subject.new(
      namespace: "Example",
      method_name: "run",
      ast_node: parse(source)
    )
  end

  def method_node(source)
    ast = parse(source)
    return ast if ast.respond_to?(:type) && %i[def defs].include?(ast.type)

    ast.children.find do |child|
      child.respond_to?(:type) && %i[def defs].include?(child.type)
    end
  end

  def method_body_node(source)
    method_node(source).children.last
  end

  def find_nodes(node, type, results = [])
    return results unless node.respond_to?(:type)

    results << node if node.type == type
    node.children.each { |child| find_nodes(child, type, results) }
    results
  end

  def explicit_return_node(source)
    find_nodes(parse(source), :return).first
  end

  def final_expression_node(source)
    method_body = method_body_node(source)
    return method_body unless method_body.type == :begin

    method_body.children.rfind { |child| child.respond_to?(:type) }
  end

  def mutate(node, subject:)
    described_class.new.mutate(node, subject:)
  end

  it "declares the return-oriented node types" do
    expect(described_class.node_types).to eq(
      %i[return send int float str dstr true false if case while until array hash]
    )
  end

  it "replaces explicit return values" do
    source = <<~RUBY
      def run
        return foo
      end
    RUBY

    mutants = mutate(explicit_return_node(source), subject: method_subject(source))

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced return value with nil",
      "replaced return value with 0",
      "replaced return value with false"
    )
  end

  it "mutates explicit boolean return values reciprocally" do
    aggregate_failures do
      true_source = <<~RUBY
        def run
          return true
        end
      RUBY

      false_source = <<~RUBY
        def run
          return false
        end
      RUBY

      true_mutants = mutate(
        explicit_return_node(true_source),
        subject: method_subject(true_source)
      )

      false_mutants = mutate(
        explicit_return_node(false_source),
        subject: method_subject(false_source)
      )

      expect(true_mutants.map(&:description)).to contain_exactly(
        "replaced return value with nil",
        "replaced return value with 0",
        "replaced return value with false"
      )
      expect(false_mutants.map(&:description)).to contain_exactly(
        "replaced return value with nil",
        "replaced return value with 0",
        "replaced return value with true"
      )
    end
  end

  it "ignores explicit return nil" do
    source = <<~RUBY
      def run
        return nil
      end
    RUBY

    mutants = mutate(explicit_return_node(source), subject: method_subject(source))

    expect(mutants).to eq([])
  end

  it "ignores bare return statements" do
    source = <<~RUBY
      def run
        return
      end
    RUBY

    mutants = mutate(explicit_return_node(source), subject: method_subject(source))

    expect(mutants).to eq([])
  end

  it "replaces implicit final expressions" do
    source = <<~RUBY
      def run
        1
        foo
      end
    RUBY

    subject = method_subject(source)
    mutants = mutate(final_expression_node(source), subject:)

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced final expression with nil",
      "replaced final expression with 0",
      "replaced final expression with false"
    )
  end

  it "does not preserve false as an equivalent final expression" do
    source = <<~RUBY
      def run
        false
      end
    RUBY

    subject = method_subject(source)
    mutants = mutate(final_expression_node(source), subject:)

    expect(mutants.map(&:description)).to contain_exactly(
      "replaced final expression with nil",
      "replaced final expression with 0",
      "replaced final expression with true"
    )
  end

  it "ignores guard-clause return nil expressions" do
    source = <<~RUBY
      def run(flag)
        return nil if flag
        :ok
      end
    RUBY

    mutants = mutate(explicit_return_node(source), subject: method_subject(source))

    expect(mutants).to eq([])
  end

  it "ignores non-final expressions in method bodies" do
    source = <<~RUBY
      def run
        foo
        bar
      end
    RUBY

    subject = method_subject(source)
    mutants = mutate(method_body_node(source).children.first, subject:)

    expect(mutants).to eq([])
  end

  it "ignores implicit final expressions when source metadata is missing" do
    subject = Henitai::Subject.new(namespace: "Example", method_name: "run")

    expect(
      mutate(parse("foo"), subject:)
    ).to eq([])
  end

  it "ignores implicit final expressions in empty methods" do
    subject = method_subject(<<~RUBY)
      def run
      end
    RUBY

    expect(
      mutate(parse("foo"), subject:)
    ).to eq([])
  end
end
