# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces relational operators with identity methods (`eql?`, `equal?`)
    # and vice versa.
    #
    # This is the noisy half of the equality/identity pairing split out of
    # EqualityOperator: most Ruby objects don't observably distinguish `==`
    # from `eql?`/`equal?`, so these mutations are frequently unkillable by
    # ordinary tests. They stay available in the full operator set rather
    # than the default light set.
    class EqualityIdentityOperator < Henitai::Operator
      NODE_TYPES = [:send].freeze
      RELATIONAL = %i[== != < > <= >= <=>].freeze
      IDENTITY = %i[eql? equal?].freeze
      OPERATORS = (RELATIONAL + IDENTITY).freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        method_name = node.children[1]
        return [] unless OPERATORS.include?(method_name)

        OPERATORS.each_with_object([]) do |replacement, mutants|
          next if replacement == method_name
          next if RELATIONAL.include?(method_name) && RELATIONAL.include?(replacement)

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
