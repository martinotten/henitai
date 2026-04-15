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
      equivalent_arithmetic_mutation?(mutant) ||
        equivalent_logical_mutation?(mutant) ||
        equivalent_singleton_equality_mutation?(mutant) ||
        equivalent_string_eql_mutation?(mutant)
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

    # Detects `lhs == <singleton>` mutated to `lhs.equal?(<singleton>)` (or the
    # reverse), but only when the receiver is itself a singleton literal.
    #
    # Both sides must be singleton literals so that we can prove, without
    # runtime type information, that `==` reduces to identity comparison.
    # A variable or arbitrary expression as the receiver is unsafe: for example
    # `1.0 == 1` is true while `1.0.equal?(1)` is false, and any object with a
    # custom `#==` can exhibit the same divergence.
    #
    # Singleton types accepted on both receiver and RHS:
    #   Symbol  – interned; only one instance of :foo ever exists in a process.
    #   nil/true/false – singletons by language specification.
    def equivalent_singleton_equality_mutation?(mutant)
      original = mutant.original_node
      mutated  = mutant.mutated_node

      equality_send?(original) && equality_send?(mutated) &&
        same_receiver?(original, mutated) &&
        singleton_literal?(original.children[0]) &&
        singleton_rhs_match?(original, mutated) &&
        equality_operators?(original.children[1], mutated.children[1])
    end

    # Detects `lhs == rhs` mutated to `lhs.eql?(rhs)` (or the reverse) when at
    # least one operand is a string literal.
    #
    # String#eql? is documented to compare both type and value. Since String#==
    # also compares type and value (it returns false for any non-String argument
    # without invoking the other object's #==), the two methods are equivalent
    # for all possible inputs whenever at least one operand is statically known
    # to be a String — proven here by the presence of a :str literal on the
    # receiver or the argument side.
    #
    # When no operand is a string literal we conservatively leave the mutant
    # pending: the receiver could be any object whose custom #== diverges from
    # its #eql?.
    def equivalent_string_eql_mutation?(mutant)
      original = mutant.original_node
      mutated  = mutant.mutated_node

      string_eql_send?(original) && string_eql_send?(mutated) &&
        same_receiver?(original, mutated) &&
        string_eql_operators?(original.children[1], mutated.children[1]) &&
        same_rhs?(original, mutated) &&
        string_operand?(original)
    end

    def string_eql_send?(node)
      node.is_a?(Parser::AST::Node) &&
        node.type == :send &&
        node.children.size == 3 &&
        string_eql_operator?(node.children[1])
    end

    def string_eql_operator?(operator)
      %i[== eql?].include?(operator)
    end

    def string_eql_operators?(op_a, op_b)
      string_eql_operator?(op_a) && string_eql_operator?(op_b) && op_a != op_b
    end

    def same_rhs?(original, mutated)
      same_node?(original.children[2], mutated.children[2])
    end

    # Returns true when at least one operand is a string literal, giving static
    # proof that the comparison is string-typed on at least one side.
    def string_operand?(node)
      string_literal?(node.children[0]) || string_literal?(node.children[2])
    end

    def string_literal?(node)
      node.is_a?(Parser::AST::Node) && node.type == :str
    end

    def singleton_rhs_match?(original, mutated)
      rhs = original.children[2]
      singleton_literal?(rhs) && same_node?(rhs, mutated.children[2])
    end

    def equality_send?(node)
      node.is_a?(Parser::AST::Node) &&
        node.type == :send &&
        node.children.size == 3 &&
        equality_operator?(node.children[1])
    end

    def equality_operator?(operator)
      %i[== equal?].include?(operator)
    end

    def equality_operators?(op_a, op_b)
      equality_operator?(op_a) && equality_operator?(op_b) && op_a != op_b
    end

    # Returns true for AST nodes that represent Ruby singleton values:
    # symbols, nil, true, and false.
    def singleton_literal?(node)
      return false unless node.is_a?(Parser::AST::Node)

      # rubocop:disable Lint/BooleanSymbol
      case node.type
      when :sym, :nil, :true, :false then true
      else false
      end
      # rubocop:enable Lint/BooleanSymbol
    end

    def same_node?(left, right)
      left == right
    end
  end
end
