# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces arithmetic operators with their mutation counterparts.
    class ArithmeticOperator < Henitai::Operator
      NODE_TYPES = [:send].freeze
      MUTATION_MATRIX = {
        :+ => :-,
        :- => :+,
        :* => :/,
        :/ => :*,
        :** => :*,
        :% => :*
      }.freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        replacement = MUTATION_MATRIX[node.children[1]]
        return [] unless replacement

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: mutated_node(node, replacement),
            description: "replaced #{node.children[1]} with #{replacement}"
          )
        ]
      end

      private

      def mutated_node(node, replacement)
        receiver = node.children[0]
        arguments = node.children[2..] || []
        Parser::AST::Node.new(node.type, [receiver, replacement, *arguments])
      end
    end
  end
end
