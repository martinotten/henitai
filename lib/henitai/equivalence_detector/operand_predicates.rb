# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  class EquivalenceDetector
    # Recognizes the arithmetic operators and neutral operands that make a
    # mutation provably equivalent to its original -- `x + 0`, `x * 1` and
    # friends.
    #
    # Extracted from EquivalenceDetector because these decisions are
    # load-bearing for scoring: a mutant marked equivalent leaves *both* sides
    # of the mutation score, so a false positive quietly changes the reported
    # number. They deserve tests of their own rather than being reached through
    # the detector's private interface.
    class OperandPredicates
      ADDITIVE = %i[+ -].freeze
      MULTIPLICATIVE = %i[* / **].freeze

      def additive_operator?(operator) = ADDITIVE.include?(operator)

      def multiplicative_operator?(operator) = MULTIPLICATIVE.include?(operator)

      # Additive identity: `x + 0` and `x - 0` both reduce to `x`.
      def zero_operand?(node) = numeric_operand?(node, 0)

      # Multiplicative identity: `x * 1`, `x / 1` and `x ** 1` all reduce to `x`.
      def one_operand?(node) = numeric_operand?(node, 1)

      private

      # Reads the right-hand operand of a binary send. Guards against a
      # malformed node whose operand is a bare Ruby value rather than an AST
      # node -- that shape does not occur in parsed source, but the detector
      # must not raise on synthesized input.
      def numeric_operand?(node, value)
        operand = node.children[2]
        return false unless operand.is_a?(Parser::AST::Node)

        case operand.type
        when :int, :float
          operand.children.first == value || operand.children.first == value.to_i
        else
          false
        end
      end
    end
  end
end
