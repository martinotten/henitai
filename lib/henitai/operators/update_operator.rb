# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Swaps compound assignment operators with their inverses.
    #
    # Covers arithmetic pairs (+=/-=, *=/=) via :op_asgn and
    # logical pairs (||=/&&=) via :or_asgn/:and_asgn. Exponent and modulo
    # compound assignments are intentionally excluded: they are not part of the
    # supported swap matrix and are already covered by other operator families
    # when appropriate.
    class UpdateOperator < Henitai::Operator
      NODE_TYPES = %i[op_asgn or_asgn and_asgn].freeze
      ARITHMETIC_SWAPS = {
        :+ => :-,
        :- => :+,
        :* => :/,
        :/ => :*
      }.freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :op_asgn
          mutate_arithmetic(node, subject:)
        when :or_asgn
          mutate_logical(node, subject:, from: "||=", to: :and_asgn, to_op: "&&=")
        when :and_asgn
          mutate_logical(node, subject:, from: "&&=", to: :or_asgn, to_op: "||=")
        else
          []
        end
      end

      private

      def mutate_arithmetic(node, subject:)
        target, operator, value = node.children
        replacement = ARITHMETIC_SWAPS[operator]
        return [] unless replacement

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:op_asgn, [target, replacement, value]),
            description: "replaced #{operator}= with #{replacement}="
          )
        ]
      end

      def mutate_logical(node, subject:, from:, to:, to_op:)
        target, value = node.children
        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(to, [target, value]),
            description: "replaced #{from} with #{to_op}"
          )
        ]
      end
    end
  end
end
