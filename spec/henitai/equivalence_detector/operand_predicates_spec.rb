# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::EquivalenceDetector::OperandPredicates do
  subject(:predicates) { described_class.new }

  def int(value) = Parser::AST::Node.new(:int, [value])
  def float(value) = Parser::AST::Node.new(:float, [value])
  def lvar(name) = Parser::AST::Node.new(:lvar, [name])
  def binary_send(receiver, operator, operand) = Parser::AST::Node.new(:send, [receiver, operator, operand])

  describe "#additive_operator?" do
    it "recognizes plus" do
      expect(predicates.additive_operator?(:+)).to be(true)
    end

    it "recognizes minus" do
      expect(predicates.additive_operator?(:-)).to be(true)
    end

    it "rejects a multiplicative operator" do
      expect(predicates.additive_operator?(:*)).to be(false)
    end
  end

  describe "#multiplicative_operator?" do
    it "recognizes times" do
      expect(predicates.multiplicative_operator?(:*)).to be(true)
    end

    it "recognizes divide" do
      expect(predicates.multiplicative_operator?(:/)).to be(true)
    end

    it "recognizes exponent" do
      expect(predicates.multiplicative_operator?(:**)).to be(true)
    end

    it "rejects an additive operator" do
      expect(predicates.multiplicative_operator?(:+)).to be(false)
    end
  end

  describe "#zero_operand?" do
    it "recognizes an integer zero" do
      expect(predicates.zero_operand?(binary_send(lvar(:value), :+, int(0)))).to be(true)
    end

    it "recognizes a float zero" do
      expect(predicates.zero_operand?(binary_send(lvar(:value), :+, float(0.0)))).to be(true)
    end

    it "rejects a non-zero integer" do
      expect(predicates.zero_operand?(binary_send(lvar(:value), :+, int(1)))).to be(false)
    end

    it "rejects a non-numeric operand" do
      expect(predicates.zero_operand?(binary_send(lvar(:value), :+, lvar(:other)))).to be(false)
    end

    # No parsed source produces this shape, but the detector must not raise on
    # a synthesized node whose operand is a bare Ruby value.
    it "rejects a malformed operand that is not an AST node" do
      malformed = Parser::AST::Node.new(:send, [lvar(:value), :+, 0])

      expect(predicates.zero_operand?(malformed)).to be(false)
    end
  end

  describe "#one_operand?" do
    it "recognizes an integer one" do
      expect(predicates.one_operand?(binary_send(lvar(:value), :*, int(1)))).to be(true)
    end

    it "recognizes a float one" do
      expect(predicates.one_operand?(binary_send(lvar(:value), :*, float(1.0)))).to be(true)
    end

    it "rejects a zero" do
      expect(predicates.one_operand?(binary_send(lvar(:value), :*, int(0)))).to be(false)
    end

    it "rejects a malformed operand that is not an AST node" do
      expect(predicates.one_operand?(Parser::AST::Node.new(:send, [lvar(:value), :*, 1]))).to be(false)
    end
  end
end
