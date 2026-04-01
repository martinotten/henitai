# frozen_string_literal: true

require "parser/current"

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
          mutate_binary(node, subject:, replacement_type: :or, from: "&&", to: "||")
        when :or
          mutate_binary(node, subject:, replacement_type: :and, from: "||", to: "&&")
        else
          []
        end
      end

      private

      def mutate_binary(node, subject:, replacement_type:, from:, to:)
        lhs, rhs = node.children

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(replacement_type, [lhs, rhs]),
            description: "replaced #{from} with #{to}"
          ),
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: lhs,
            description: "replaced #{from} with lhs"
          ),
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: rhs,
            description: "replaced #{from} with rhs"
          )
        ]
      end
    end
  end
end
