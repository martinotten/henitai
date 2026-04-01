# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Mutates case-match arms and removes pattern guards.
    class PatternMatch < Henitai::Operator
      NODE_TYPES = [:case_match].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] unless node.type == :case_match

        mutants = []
        arm_number = 0

        node.children.each_with_index do |child, index|
          next unless child&.type == :in_pattern

          arm_number += 1
          mutants << remove_in_arm(node, subject:, index:, arm_number:)

          guard = child.children[1]
          next unless guard

          mutants << remove_guard(node, subject:, index:, arm_number:, child:)
        end

        mutants
      end

      private

      def remove_in_arm(node, subject:, index:, arm_number:)
        children = node.children.dup
        children.delete_at(index)

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:case_match, children),
          description: "removed in arm #{arm_number}"
        )
      end

      def remove_guard(node, subject:, index:, arm_number:, child:)
        children = node.children.dup
        children[index] = mutated_arm(child)

        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:case_match, children),
          description: "removed pattern guard #{arm_number}"
        )
      end

      def mutated_arm(node)
        pattern, _guard, body = node.children
        Parser::AST::Node.new(:in_pattern, [pattern, nil, body])
      end
    end
  end
end
