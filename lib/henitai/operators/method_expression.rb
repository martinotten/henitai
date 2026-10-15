# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces generic method call results with nil.
    #
    # A call with a block is replaced together with its block: replacing only
    # the call would leave +nil { ... }+ behind, which does not parse.
    class MethodExpression < Henitai::Operator
      NODE_TYPES = %i[send block numblock].freeze
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
        call = called_method(node)
        return [] unless call&.type == :send

        _receiver, method_name, *_arguments = call.children
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

      def called_method(node)
        case node.type
        when :send then node
        when :block, :numblock then node.children.first
        end
      end

      def excluded_method?(method_name)
        method_name.to_s.end_with?("=") || EXCLUDED_METHODS.include?(method_name)
      end
    end
  end
end
