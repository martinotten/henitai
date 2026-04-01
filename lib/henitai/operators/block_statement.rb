# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Removes the body of normal block statements.
    class BlockStatement < Henitai::Operator
      NODE_TYPES = [:block].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] if node.children.last.nil?

        call, args, _body = node.children

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:block, [call, args, nil]),
            description: "removed block content"
          )
        ]
      end
    end
  end
end
