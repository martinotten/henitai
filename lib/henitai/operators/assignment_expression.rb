# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Reduces ||= to a plain assignment, removing the memoization guard.
    #
    # Arithmetic compound assignments (+=, -=, *=, /=) are covered by
    # UpdateOperator, which also handles the logical pair swap (||= ↔ &&=).
    # AssignmentExpression is intentionally scoped to or_asgn reduction only
    # to avoid emitting duplicate mutants in the full operator set.
    class AssignmentExpression < Henitai::Operator
      NODE_TYPES = %i[or_asgn].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :or_asgn
          # Memoization-style ||= is usually filtered earlier by AridNodeFilter.
          mutate_coalesce_assignment(node, subject:)
        else
          []
        end
      end

      private

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
