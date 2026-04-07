# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Removes unary prefix operators by replacing the send node with its receiver.
    #
    # Covers :-@ (unary minus) and :~ (bitwise NOT).
    # Unary negation (!) is intentionally excluded — BooleanLiteral owns that.
    class UnaryOperator < Henitai::Operator
      NODE_TYPES = %i[send].freeze
      UNARY_METHODS = %i[-@ ~].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        receiver, method_name, *arguments = node.children
        return [] unless UNARY_METHODS.include?(method_name)
        return [] unless arguments.empty?
        return [] unless receiver

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: receiver,
            description: "removed unary #{method_name.to_s.delete('@')}"
          )
        ]
      end
    end
  end
end
