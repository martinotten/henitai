# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces relational/equality operators with the other relational operators.
    #
    # Identity-method comparisons (`eql?`, `equal?`) are handled separately by
    # EqualityIdentityOperator: that pairing is the hardest to kill in practice
    # (most objects don't observably distinguish `==` from `eql?`/`equal?`), so
    # it is kept out of the default light set.
    class EqualityOperator < Henitai::Operator
      NODE_TYPES = [:send].freeze
      OPERATORS = %i[== != < > <= >= <=>].freeze

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
        arguments = node.children[2..]
        Parser::AST::Node.new(:send, [receiver, replacement, *arguments])
      end
    end
  end
end
