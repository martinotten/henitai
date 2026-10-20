# frozen_string_literal: true

require_relative "parser_current"
require_relative "equivalence_detector/operand_predicates"

module Henitai
  # Detects obvious equivalent mutants before execution.
  #
  # The detector is intentionally conservative: it only marks a mutation as
  # equivalent when the AST shape and the literal operands prove the
  # equivalence for every runtime value. Each rule below states the argument
  # that makes it sound; a rule that cannot state one is not implemented.
  #
  # Rules:
  #   * Additive identity, `n + 0` <-> `n - 0`, when `n` is an Integer literal
  #     or a non-negative-zero Float literal. Both return `n`.
  #   * Multiplicative identity, `n * 1` <-> `n / 1` <-> `n ** 1`, under the
  #     same receiver condition. Both return `n`.
  #   * Left-literal logical identity, `false || x` -> `x` and `true && x` -> `x`.
  #     `false || x` is `x` for every `x`, and `true && x` is `x` for every `x`.
  #     The right-literal forms are unsound: `nil || false` is `false` and
  #     `5 && true` is `true`.
  #   * Singleton equality, `s == v` <-> `s.equal?(v)` when `s` and `v` are
  #     Symbol, nil, true or false literals. These values are unique instances,
  #     so `==` reduces to identity.
  #   * String equality, `"a" == "b"` <-> `"a".eql?("b")` when both operands are
  #     String literals. Both compare type and value for two Strings.
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
        zero_operand?(mutated) &&
        numeric_receiver?(original)
    end

    def multiplicative_equivalent?(original, mutated)
      multiplicative_operator?(original.children[1]) &&
        multiplicative_operator?(mutated.children[1]) &&
        one_operand?(original) &&
        one_operand?(mutated) &&
        numeric_receiver?(original)
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

    # `false || x` is `x` for every `x`. The right-literal form `x || false` is
    # not: `nil || false` is `false`, not `nil`.
    def false_identity_equivalent?(original, mutated)
      false_operand?(original.children[0]) && same_node?(mutated, original.children[1])
    end

    # `true && x` is `x` for every `x`. The right-literal form `x && true` is
    # not: `5 && true` is `true`, not `5`.
    def true_identity_equivalent?(original, mutated)
      true_operand?(original.children[0]) && same_node?(mutated, original.children[1])
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

    def additive_operator?(operator) = operand_predicates.additive_operator?(operator)

    def multiplicative_operator?(operator) = operand_predicates.multiplicative_operator?(operator)

    def zero_operand?(node) = operand_predicates.zero_operand?(node)

    def one_operand?(node) = operand_predicates.one_operand?(node)

    def numeric_receiver?(node) = operand_predicates.numeric_receiver?(node.children[0])

    def operand_predicates = @operand_predicates ||= OperandPredicates.new

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

    # Detects `lhs == rhs` mutated to `lhs.eql?(rhs)` (or the reverse) when both
    # operands are string literals.
    #
    # With two String literals, neither `==` nor `eql?` can reach a custom
    # method, so both compare type and value and return the same result. A
    # single string literal is not enough: an unknown receiver can override
    # `==`, and `"a" == obj` calls `obj == "a"` when obj responds to `to_str`.
    def equivalent_string_eql_mutation?(mutant)
      original = mutant.original_node
      mutated  = mutant.mutated_node

      string_eql_swap?(original, mutated) &&
        string_literal?(original.children[0]) &&
        string_literal?(original.children[2])
    end

    def string_eql_swap?(original, mutated)
      string_eql_send?(original) && string_eql_send?(mutated) &&
        same_receiver?(original, mutated) &&
        string_eql_operators?(original.children[1], mutated.children[1]) &&
        same_rhs?(original, mutated)
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
