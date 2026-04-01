# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Replaces string literals with neutral alternatives.
    class StringLiteral < Henitai::Operator
      NODE_TYPES = %i[str dstr].freeze
      REPLACEMENTS = ["", "Henitai was here"].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :str
          mutate_plain_string(node, subject:)
        when :dstr
          mutate_interpolated_string(node, subject:)
        else
          []
        end
      end

      private

      def mutate_plain_string(node, subject:)
        REPLACEMENTS.map do |replacement|
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:str, [replacement]),
            description: "replaced string with #{replacement.inspect}"
          )
        end
      end

      def mutate_interpolated_string(node, subject:)
        replacement = static_string(node)

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:str, [replacement]),
            description: "removed interpolation from string"
          )
        ]
      end

      def static_string(node)
        # Fully interpolated strings collapse to an empty string, which still
        # gives us a valid neutral mutation target.
        node.children.each_with_object(+"") do |child, string|
          next unless child.type == :str

          string << child.children.first.to_s
        end
      end
    end
  end
end
