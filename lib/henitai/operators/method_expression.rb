# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Replaces generic method call results with nil.
    class MethodExpression < Henitai::Operator
      NODE_TYPES = [:send].freeze
      EXCLUDED_METHODS = %i[
        +
        -
        *
        /
        **
        %
        ==
        !=
        <
        >
        <=
        >=
        <=>
        eql?
        equal?
        !
      ].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] unless node.type == :send

        _receiver, method_name, *_arguments = node.children
        return [] if excluded_method?(method_name)

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:nil, []),
            description: "replaced method call with nil"
          )
        ]
      end

      private

      def excluded_method?(method_name)
        method_name.to_s.end_with?("=") || EXCLUDED_METHODS.include?(method_name)
      end
    end
  end
end
