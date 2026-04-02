# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces comparison operators with the other comparison operators.
    class EqualityOperator < Henitai::Operator
      NODE_TYPES = [:send].freeze
      OPERATORS = %i[== != < > <= >= <=> eql? equal?].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        method_name = node.children[1]
        return [] unless OPERATORS.include?(method_name)

        OPERATORS.each_with_object([]) do |replacement, mutants|
          next if replacement == method_name

          mutants << build_mutant(
            subject:,
            original_node: node,
            mutated_node: mutated_node(node, replacement),
            description: "replaced #{method_name} with #{replacement}"
          )
        end
      end

      private

      def mutated_node(node, replacement)
        receiver = node.children[0]
        arguments = node.children[2..] || []
        Parser::AST::Node.new(:send, [receiver, replacement, *arguments])
      end
    end
  end
end
