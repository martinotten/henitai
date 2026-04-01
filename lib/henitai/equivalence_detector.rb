# frozen_string_literal: true

require "parser/current"

module Henitai
  # Detects obvious equivalent mutants before execution.
  #
  # The detector is intentionally conservative: it only marks mutations as
  # equivalent when the AST shape and the operand literals make the equivalence
  # obvious enough to be useful.
  class EquivalenceDetector
    EQUIVALENT_ARITHMETIC_OPERATORS = %i[+ - * / **].freeze

    def analyze(mutant)
      return mutant unless equivalent_arithmetic_mutation?(mutant)

      mutant.status = :equivalent
      mutant
    end

    private

    def equivalent_arithmetic_mutation?(mutant)
      original = mutant.original_node
      mutated = mutant.mutated_node
      return false unless binary_send?(original) && binary_send?(mutated)
      return false unless same_receiver_and_operand?(original, mutated)

      (zero_operand?(original) && zero_operand?(mutated)) ||
        (one_operand?(original) && one_operand?(mutated))
    end

    def binary_send?(node)
      node.is_a?(Parser::AST::Node) && node.type == :send && node.children.size >= 3
    end

    def same_receiver_and_operand?(original, mutated)
      same_node?(original.children[0], mutated.children[0]) &&
        same_node?(original.children[2], mutated.children[2]) &&
        equivalent_arithmetic_operator?(original.children[1]) &&
        equivalent_arithmetic_operator?(mutated.children[1])
    end

    def equivalent_arithmetic_operator?(operator)
      EQUIVALENT_ARITHMETIC_OPERATORS.include?(operator)
    end

    def zero_operand?(node)
      numeric_operand?(node, 0)
    end

    def one_operand?(node)
      numeric_operand?(node, 1)
    end

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

    def same_node?(left, right)
      left == right
    end
  end
end
