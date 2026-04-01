# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Toggles boolean literals and removes unary negation.
    class BooleanLiteral < Henitai::Operator
      NODE_TYPES = %i[true false send].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :true
          [build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:false, []),
            description: "replaced true with false"
          )]
        when :false
          [build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:true, []),
            description: "replaced false with true"
          )]
        when :send
          mutate_negation(node, subject:)
        else
          []
        end
      end

      private

      def mutate_negation(node, subject:)
        receiver, method_name, *arguments = node.children
        return [] unless method_name == :! && arguments.empty?
        return [] unless receiver

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: receiver,
            description: "removed negation"
          )
        ]
      end
    end
  end
end
