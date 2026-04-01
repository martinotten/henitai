# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Flips inclusive and exclusive range operators.
    class RangeLiteral < Henitai::Operator
      NODE_TYPES = %i[irange erange].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :irange
          mutate_range(node, subject:, replacement_type: :erange, from: "..", to: "...")
        when :erange
          mutate_range(node, subject:, replacement_type: :irange, from: "...", to: "..")
        else
          []
        end
      end

      private

      def mutate_range(node, subject:, replacement_type:, from:, to:)
        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(replacement_type, node.children),
            description: "replaced #{from} with #{to}"
          )
        ]
      end
    end
  end
end
