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

  describe "#numeric_receiver?" do
    # Integer arithmetic on a receiver that is an Integer literal always returns
    # the receiver for the neutral operand, so the identity holds.
    it "recognizes an integer literal" do
      expect(predicates.numeric_receiver?(int(7))).to be(true)
    end

    # A positive float literal is a number, and `x + 0`, `x - 0` return `x`.
    it "recognizes a positive float literal" do
      expect(predicates.numeric_receiver?(float(2.5))).to be(true)
    end

    # `-0.0 + 0` is `0.0` while `-0.0 - 0` is `-0.0`, so the identity breaks.
    it "rejects negative zero" do
      expect(predicates.numeric_receiver?(float(-0.0))).to be(false)
    end

    it "accepts positive zero" do
      expect(predicates.numeric_receiver?(float(0.0))).to be(true)
    end

    # A variable may hold a String (`"ab" * 1` is "ab", `"ab" / 1` raises) or
    # any object with its own operators, so it proves nothing.
    it "rejects a variable receiver" do
      expect(predicates.numeric_receiver?(lvar(:value))).to be(false)
    end

    it "rejects a string literal receiver" do
      expect(predicates.numeric_receiver?(Parser::AST::Node.new(:str, ["ab"]))).to be(false)
    end

    it "rejects a non-AST receiver" do
      expect(predicates.numeric_receiver?(nil)).to be(false)
    end
  end
end
