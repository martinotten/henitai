# frozen_string_literal: true

require_relative "parser_current"

module Henitai
  # Detects obvious equivalent mutants before execution.
  #
  # The detector is intentionally conservative: it only marks mutations as
  # equivalent when the AST shape and the operand literals make the equivalence
  # obvious enough to be useful.
  class EquivalenceDetector
    def analyze(mutant)
      return mutant unless equivalent_mutation?(mutant)

      mutant.status = :equivalent
      mutant
    end

    private

    def equivalent_mutation?(mutant)
      equivalent_arithmetic_mutation?(mutant) || equivalent_logical_mutation?(mutant)
    end

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

    def equivalent_logical_mutation?(mutant)
      original = mutant.original_node
      mutated = mutant.mutated_node
      return false unless logical_node?(original)

      logical_identity_equivalent?(original, mutated)
    end

    def logical_node?(node)
      node.is_a?(Parser::AST::Node) && %i[and or].include?(node.type)
    end

    def logical_identity_equivalent?(original, mutated)
      case original.type
      when :or
        false_identity_equivalent?(original, mutated)
      when :and
        true_identity_equivalent?(original, mutated)
      else
        false
      end
    end

    def false_identity_equivalent?(original, mutated)
      return true if false_operand?(original.children[0]) && same_node?(mutated, original.children[1])
      return true if false_operand?(original.children[1]) && same_node?(mutated, original.children[0])

      false
    end

    def true_identity_equivalent?(original, mutated)
      return true if true_operand?(original.children[0]) && same_node?(mutated, original.children[1])
      return true if true_operand?(original.children[1]) && same_node?(mutated, original.children[0])

      false
    end

    def false_operand?(node)
      # Parser uses :true / :false node types, so the AST symbols are intentional.
      # rubocop:disable Lint/BooleanSymbol
      boolean_literal?(node, :false)
      # rubocop:enable Lint/BooleanSymbol
    end

    def true_operand?(node)
      # Parser uses :true / :false node types, so the AST symbols are intentional.
      # rubocop:disable Lint/BooleanSymbol
      boolean_literal?(node, :true)
      # rubocop:enable Lint/BooleanSymbol
    end

    def boolean_literal?(node, type)
      node.is_a?(Parser::AST::Node) && node.type == type && node.children.empty?
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
