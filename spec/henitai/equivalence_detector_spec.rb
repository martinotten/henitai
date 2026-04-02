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

  it "marks addition and subtraction by zero as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :+, int(0)),
      mutated_node: binary_send(lvar(:value), :-, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:equivalent)
  end

  it "marks multiplication and division by one as equivalent" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, float(1.0)),
      mutated_node: binary_send(lvar(:value), :/, float(1.0))
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

  it "keeps mismatched neutral arithmetic operators pending" do
    mutant = build_mutant(
      original_node: binary_send(lvar(:value), :*, int(0)),
      mutated_node: binary_send(lvar(:value), :+, int(0))
    )

    described_class.new.analyze(mutant)

    expect(mutant.status).to eq(:pending)
  end
end
