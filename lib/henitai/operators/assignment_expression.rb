# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Mutates compound assignments and reduces ||= to a plain assignment.
    class AssignmentExpression < Henitai::Operator
      NODE_TYPES = %i[op_asgn or_asgn].freeze
      OPERATOR_MAP = {
        :+ => :-,
        :- => :+
      }.freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :op_asgn
          mutate_compound_assignment(node, subject:)
        when :or_asgn
          # Memoization-style ||= is usually filtered earlier by AridNodeFilter.
          mutate_coalesce_assignment(node, subject:)
        else
          []
        end
      end

      private

      def mutate_compound_assignment(node, subject:)
        left, operator, right = node.children
        replacement = OPERATOR_MAP[operator]
        return [] unless replacement

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:op_asgn, [left, replacement, right]),
            description: "replaced #{operator} with #{replacement}"
          )
        ]
      end

      def mutate_coalesce_assignment(node, subject:)
        left, right = node.children
        mutated_node = assignment_node(left, right)
        return [] unless mutated_node

        [
          build_mutant(
            subject:,
            original_node: node,
            mutated_node:,
            description: "removed ||="
          )
        ]
      end

      def assignment_node(left, right)
        case left.type
        when :lvasgn, :ivasgn, :gvasgn, :cvasgn
          Parser::AST::Node.new(left.type, [left.children.first, right])
        when :casgn
          namespace, name = left.children
          Parser::AST::Node.new(:casgn, [namespace, name, right])
        when :send
          assignment_name = left.children[1] == :[] ? :[]= : :"#{left.children[1]}="
          receiver, _method_name, *arguments = left.children
          Parser::AST::Node.new(:send, [receiver, assignment_name, *arguments, right])
        end
      end
    end
  end
end
