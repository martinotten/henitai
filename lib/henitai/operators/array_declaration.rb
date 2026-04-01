# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Removes array elements or replaces empty arrays with a nil element.
    class ArrayDeclaration < Henitai::Operator
      NODE_TYPES = [:array].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] unless node.type == :array

        if node.children.empty?
          [empty_array_mutant(subject:, node:)]
        else
          [empty_array_mutant(subject:, node:)] + remove_element_mutants(node, subject:)
        end
      end

      private

      def empty_array_mutant(subject:, node:)
        replacement = node.children.empty? ? [Parser::AST::Node.new(:nil, [])] : []
        description = node.children.empty? ? "replaced empty array with [nil]" : "replaced array with empty array"

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:array, replacement),
          description:
        )
      end

      def remove_element_mutants(node, subject:)
        node.children.each_with_index.map do |_element, index|
          children = node.children.dup
          children.delete_at(index)

          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:array, children),
            description: "removed array element #{index + 1}"
          )
        end
      end
    end
  end
end
