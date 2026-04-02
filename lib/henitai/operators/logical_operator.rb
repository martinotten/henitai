# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces short-circuit logical operators and collapses them to operands.
    class LogicalOperator < Henitai::Operator
      NODE_TYPES = %i[and or].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :and
          mutate_and(node, subject:)
        when :or
          mutate_or(node, subject:)
        else
          []
        end
      end

      private

      def mutate_and(node, subject:)
        mutate_binary(node, subject:, replacement_type: :or, from: "&&", to: "||")
      end

      def mutate_or(node, subject:)
        mutate_binary(node, subject:, replacement_type: :and, from: "||", to: "&&")
      end

      def mutate_binary(node, subject:, replacement_type:, from:, to:)
        [
          build_replaced_operator_mutant(
            node,
            subject:,
            replacement_type:,
            from:,
            to:
          ),
          build_replaced_lhs_mutant(node, subject:, from:),
          build_replaced_rhs_mutant(node, subject:, from:)
        ]
      end

      def build_replaced_operator_mutant(node, subject:, replacement_type:, from:, to:)
        lhs, rhs = node.children

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(replacement_type, [lhs, rhs]),
          description: "replaced #{from} with #{to}"
        )
      end

      def build_replaced_lhs_mutant(node, subject:, from:)
        lhs, = node.children

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: lhs,
          description: "replaced #{from} with lhs"
        )
      end

      def build_replaced_rhs_mutant(node, subject:, from:)
        _, rhs = node.children

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: rhs,
          description: "replaced #{from} with rhs"
        )
      end
    end
  end
end
