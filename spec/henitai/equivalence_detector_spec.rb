# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::EquivalenceDetector do
  def build_mutant(original_node:, mutated_node:)
    Struct.new(:original_node, :mutated_node, :status).new(
      original_node,
      mutated_node,
      :pending
    )
  end

  def binary_send(receiver, operator, operand)
    Parser::AST::Node.new(:send, [receiver, operator, operand])
  end

  def lvar(name)
    Parser::AST::Node.new(:lvar, [name])
  end

  def int(value)
    Parser::AST::Node.new(:int, [value])
  end

  def float(value)
    Parser::AST::Node.new(:float, [value])
  end

  def boolean(value)
    # Parser uses :true / :false node types, so the AST symbols are intentional.
    # rubocop:disable Lint/BooleanSymbol
    Parser::AST::Node.new(value ? :true : :false, [])
    # rubocop:enable Lint/BooleanSymbol
  end

  def csend(receiver, operator, operand)
    Parser::AST::Node.new(:csend, [receiver, operator, operand])
  end

  def malformed_zero_node
    Parser::AST::Node.new(:str, [0])
  end

  def malformed_one_node
    Parser::AST::Node.new(:sym, [1])
  end

  def duck_false_node
    # Parser uses :true / :false node types, so the AST symbols are intentional.
    # rubocop:disable Lint/BooleanSymbol
    Struct.new(:type, :children).new(:false, [])
    # rubocop:enable Lint/BooleanSymbol
  end

  def duck_true_node
    # Parser uses :true / :false node types, so the AST symbols are intentional.
    # rubocop:disable Lint/BooleanSymbol
    Struct.new(:type, :children).new(:true, [])
    # rubocop:enable Lint/BooleanSymbol
  end

  def wrong_type_ast_node
    Parser::AST::Node.new(:sym, [])
  end

  it "marks addition and subtraction by zero as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: binary_send(lvar(:value), :-, int(0))
    )

    aggregate_failures do
      result = described_class.new.analyze(mutant)
      expect(result).to equal(mutant)
      expect(mutant.status).to eq(:equivalent)
    end
  end

  it "marks multiplication and division by one as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, float(1.0)),
      mutated_node: binary_send(lvar(:value), :/, float(1.0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks exponentiation by one as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :**, int(1)),
      mutated_node: binary_send(lvar(:value), :*, int(1))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "keeps non-neutral arithmetic mutants pending" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(2)),
      mutated_node: binary_send(lvar(:value), :-, int(2))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps non-binary mutated arithmetic nodes pending" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: int(0)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps arithmetic mutants pending when the original node is not binary" do
    mutant = build_mutant(
      original_node: lvar(:value),
      mutated_node: binary_send(lvar(:value), :+, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps mismatched neutral arithmetic operators pending" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, int(0)),
      mutated_node: binary_send(lvar(:value), :+, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps arithmetic mutants pending when the mutated node is not a plain send" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: csend(lvar(:value), :+, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps arithmetic mutants pending when receivers differ" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: binary_send(lvar(:other), :-, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps additive mutants pending unless the original operand is zero" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(1)),
      mutated_node: binary_send(lvar(:value), :-, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps additive mutants pending when the mutated operator is not additive" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: binary_send(lvar(:value), :*, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps multiplicative mutants pending unless the original operand is one" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, int(2)),
      mutated_node: binary_send(lvar(:value), :/, int(1))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps multiplicative mutants pending when the mutated operator is not multiplicative" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, int(1)),
      mutated_node: binary_send(lvar(:value), :+, int(1))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "recognizes multiplicative arithmetic operators" do
    detector = described_class.new

    expect(detector.send(:multiplicative_operator?, :**)).to be(true)
  end

  it "recognizes one as the multiplicative neutral operand" do
    detector = described_class.new
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, int(1)),
      mutated_node: binary_send(lvar(:value), :*, int(1))
    )

    expect(detector.send(:one_operand?, mutant.original_node)).to be(true)
  end

  it "rejects non-numeric operands for additive equivalence" do
    detector = described_class.new
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, lvar(:other)),
      mutated_node: binary_send(lvar(:value), :-, lvar(:other))
    )

    expect(detector.send(:zero_operand?, mutant.original_node)).to be(false)
  end

  it "rejects malformed operands for neutral arithmetic checks" do
    detector = described_class.new
    malformed = Parser::AST::Node.new(:send, [lvar(:value), :+, 0])

    expect(detector.send(:zero_operand?, malformed)).to be(false)
  end

  it "keeps additive mutants pending with a malformed zero-like operand" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, malformed_zero_node),
      mutated_node: binary_send(lvar(:value), :-, malformed_zero_node)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps multiplicative mutants pending with a malformed one-like operand" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, malformed_one_node),
      mutated_node: binary_send(lvar(:value), :/, malformed_one_node)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "marks disjunctions with false as equivalent when collapsed to the lhs" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:or, [lvar(:value), boolean(false)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks disjunctions with false as equivalent when collapsed to the rhs" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:or, [boolean(false), lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks conjunctions with true as equivalent when collapsed to the lhs" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:and, [lvar(:value), boolean(true)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks conjunctions with true as equivalent when collapsed to the rhs" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:and, [boolean(true), lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  # ---------------------------------------------------------------------------
  # Singleton equality: == <-> equal? on singleton RHS
  # ---------------------------------------------------------------------------

  def sym(name)
    Parser::AST::Node.new(:sym, [name])
  end

  def nil_node
    Parser::AST::Node.new(:nil, [])
  end

  def malformed_false_node
    # Parser uses :true / :false node types, so the AST symbols are intentional.
    # rubocop:disable Lint/BooleanSymbol
    Parser::AST::Node.new(:false, [lvar(:unexpected)])
    # rubocop:enable Lint/BooleanSymbol
  end

  def malformed_true_node
    # Parser uses :true / :false node types, so the AST symbols are intentional.
    # rubocop:disable Lint/BooleanSymbol
    Parser::AST::Node.new(:true, [lvar(:unexpected)])
    # rubocop:enable Lint/BooleanSymbol
  end

  it "marks `:sym == :sym` mutated to `:sym.equal?(:sym)` as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(sym(:ok), :==, sym(:ok)),
      mutated_node: binary_send(sym(:ok), :equal?, sym(:ok))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks `:sym.equal?(:sym)` mutated to `:sym == :sym` as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(sym(:ok), :equal?, sym(:ok)),
      mutated_node: binary_send(sym(:ok), :==, sym(:ok))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks `nil == nil` mutated to `nil.equal?(nil)` as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(nil_node, :==, nil_node),
      mutated_node: binary_send(nil_node, :equal?, nil_node)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks `true == true` mutated to `true.equal?(true)` as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(boolean(true), :==, boolean(true)),
      mutated_node: binary_send(boolean(true), :equal?, boolean(true))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks `false == false` mutated to `false.equal?(false)` as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(boolean(false), :==, boolean(false)),
      mutated_node: binary_send(boolean(false), :equal?, boolean(false))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "keeps a large integer equality swap pending" do
    mutant = build_mutant(
      original_node: binary_send(int(10**100), :==, int(10**100)),
      mutated_node: binary_send(int(10**100), :equal?, int(10**100))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps a same-operator singleton comparison pending" do
    mutant = build_mutant(
      original_node: binary_send(sym(:ok), :==, sym(:ok)),
      mutated_node: binary_send(sym(:ok), :==, sym(:ok))
    )

    aggregate_failures do
      result = described_class.new.analyze(mutant)
      expect(result).to equal(mutant)
      expect(mutant.status).to eq(:pending)
    end
  end

  it "keeps equality mutants pending when the receiver is not a singleton literal" do
    receiver = Object.new
    mutant = build_mutant(
      original_node: binary_send(receiver, :==, receiver),
      mutated_node: binary_send(receiver, :equal?, receiver)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps equality sends with extra arguments pending" do
    receiver = sym(:ok)
    extra_argument = sym(:extra)
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:send, [receiver, :==, receiver, extra_argument]),
      mutated_node: Parser::AST::Node.new(:send, [receiver, :equal?, receiver, extra_argument])
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps disjunctions with malformed false-like operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:or, [malformed_false_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps disjunctions with duck-typed false-like operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:or, [duck_false_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps disjunctions with wrong-type AST operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:or, [wrong_type_ast_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps conjunctions with malformed true-like operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:and, [malformed_true_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps conjunctions with duck-typed true-like operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:and, [duck_true_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps conjunctions with wrong-type AST operands pending" do
    mutant = build_mutant(
      original_node: Parser::AST::Node.new(:and, [wrong_type_ast_node, lvar(:value)]),
      mutated_node: lvar(:value)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps `lhs == :sym` mutated to `lhs.equal?(:sym)` pending when receiver is a variable" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:result), :==, sym(:ok)),
      mutated_node: binary_send(lvar(:result), :equal?, sym(:ok))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps `lhs == rhs` mutated to `lhs.equal?(rhs)` pending when rhs is a string literal" do
    string_node = Parser::AST::Node.new(:str, ["hello"])
    mutant = build_mutant(
      original_node: binary_send(lvar(:x), :==, string_node),
      mutated_node: binary_send(lvar(:x), :equal?, string_node)
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps `lhs == rhs` mutated to `lhs.equal?(rhs)` pending when rhs is a variable" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:x), :==, lvar(:other)),
      mutated_node: binary_send(lvar(:x), :equal?, lvar(:other))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps `lhs == :sym` mutated to `lhs.equal?(:other)` pending when symbols differ" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:x), :==, sym(:foo)),
      mutated_node: binary_send(lvar(:x), :equal?, sym(:bar))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end

  it "keeps `lhs == :sym` mutated to `lhs.equal?(:sym)` pending when receivers differ" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:x), :==, sym(:foo)),
      mutated_node: binary_send(lvar(:y), :equal?, sym(:foo))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end
end
