# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Removes the nil guard from safe navigation calls.
    class SafeNavigation < Henitai::Operator
      NODE_TYPES = [:csend].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] unless node.type == :csend

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: mutated_node(node),
            description: "removed nil guard"
          )
        ]
      end

      private

      def mutated_node(node)
        receiver, method_name, *arguments = node.children
        Parser::AST::Node.new(:send, [receiver, method_name, *arguments])
      end
    end
  end
end
