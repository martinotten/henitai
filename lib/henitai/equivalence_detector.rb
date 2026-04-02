# frozen_string_literal: true

require "parser/current"

module Henitai
  # Detects obvious equivalent mutants before execution.
  #
  # The detector is intentionally conservative: it only marks mutations as
  # equivalent when the AST shape and the operand literals make the equivalence
  # obvious enough to be useful.
  class EquivalenceDetector
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
      return false unless same_receiver?(original, mutated)

      additive_equivalent?(original, mutated) ||
        multiplicative_equivalent?(original, mutated)
    end

    def binary_send?(node)
      node.is_a?(Parser::AST::Node) && node.type == :send && node.children.size >= 3
    end

    def same_receiver?(original, mutated)
      same_node?(original.children[0], mutated.children[0])
    end

    def additive_equivalent?(original, mutated)
      additive_operator?(original.children[1]) &&
        additive_operator?(mutated.children[1]) &&
        zero_operand?(original) &&
        zero_operand?(mutated)
    end

    def multiplicative_equivalent?(original, mutated)
      multiplicative_operator?(original.children[1]) &&
        multiplicative_operator?(mutated.children[1]) &&
        one_operand?(original) &&
        one_operand?(mutated)
    end

    def additive_operator?(operator)
      %i[+ -].include?(operator)
    end

    def multiplicative_operator?(operator)
      %i[* / **].include?(operator)
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
