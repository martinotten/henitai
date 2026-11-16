# frozen_string_literal: true

require_relative "../parser_current"

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
          mutate_plain_string(node, node.children.first, subject:)
        when :dstr
          mutate_dstr(node, subject:)
        else
          []
        end
      end

      private

      # Adjacent literals and heredocs without interpolation parse as a +dstr+
      # of +str+ parts. Collapsing their "interpolation" would reproduce the
      # original string -- an equivalent mutant -- so they are mutated like a
      # plain string with the concatenated value.
      def mutate_dstr(node, subject:)
        return mutate_plain_string(node, static_string(node), subject:) if static?(node)

        mutate_interpolated_string(node, subject:)
      end

      def static?(node)
        node.children.all? { |child| child.type == :str }
      end

      def mutate_plain_string(node, original_value, subject:)
        REPLACEMENTS.reject { |r| r == original_value }.map do |replacement|
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
