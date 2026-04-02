# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Toggles boolean literals and removes unary negation.
    class BooleanLiteral < Henitai::Operator
      NODE_TYPES = %i[true false send].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        # Parser uses :true / :false node types, so the AST symbols are intentional.
        # rubocop:disable Lint/BooleanSymbol
        case node.type
        when :true
          [mutate_true_literal(node, subject:)]
        when :false
          [mutate_false_literal(node, subject:)]
        when :send
          mutate_negation(node, subject:)
        else
          []
        end
        # rubocop:enable Lint/BooleanSymbol
      end

      private

      # Parser uses :true / :false node types, so the AST symbols are intentional.
      # rubocop:disable Lint/BooleanSymbol
      def mutate_true_literal(node, subject:)
        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:false, []),
          description: "replaced true with false"
        )
      end

      def mutate_false_literal(node, subject:)
        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:true, []),
          description: "replaced false with true"
        )
      end
      # rubocop:enable Lint/BooleanSymbol

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
