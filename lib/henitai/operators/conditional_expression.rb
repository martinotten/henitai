# frozen_string_literal: true

require "parser/current"

module Henitai
  module Operators
    # Rewrites conditional expressions and loop guards.
    class ConditionalExpression < Henitai::Operator
      NODE_TYPES = %i[if case while until].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :if
          mutate_if(node, subject:)
        when :case
          mutate_case(node, subject:)
        when :while, :until
          mutate_loop(node, subject:)
        else
          []
        end
      end

      private

      def mutate_if(node, subject:)
        condition, then_branch, else_branch = node.children
        mutations = condition_variants(node, subject:, condition:)

        mutations << branch_mutant(
          subject:,
          node:,
          replacement: then_branch,
          description: "removed else branch"
        ) if then_branch && else_branch

        mutations << branch_mutant(
          subject:,
          node:,
          replacement: else_branch || nil_node,
          description: "removed then branch"
        ) if then_branch

        mutations
      end

      def mutate_case(node, subject:)
        condition, when_node, else_branch = node.children
        mutations = condition_variants(node, subject:, condition:)

        if when_node&.type == :when
          mutations << branch_mutant(
            subject:,
            node:,
            replacement: when_node.children.last || nil_node,
            description: "kept when branch"
          )
        end

        mutations << branch_mutant(
          subject:,
          node:,
          replacement: else_branch || nil_node,
          description: "kept else branch"
        ) if else_branch

        mutations
      end

      def mutate_loop(node, subject:)
        condition = node.children.first
        condition_variants(node, subject:, condition:)
      end

      def condition_variants(node, subject:, condition:)
        [
          branch_mutant(
            subject:,
            node:,
            replacement: with_condition(node, Parser::AST::Node.new(:true, [])),
            description: "replaced condition with true"
          ),
          branch_mutant(
            subject:,
            node:,
            replacement: with_condition(node, Parser::AST::Node.new(:false, [])),
            description: "replaced condition with false"
          ),
          branch_mutant(
            subject:,
            node:,
            replacement: with_condition(node, negate(condition)),
            description: "negated condition"
          )
        ]
      end

      def branch_mutant(subject:, node:, replacement:, description:)
        build_mutant(
          subject:,
          original_node: node,
          mutated_node: replacement,
          description:
        )
      end

      def with_condition(node, replacement_condition)
        children = node.children.dup
        children[0] = replacement_condition
        Parser::AST::Node.new(node.type, children)
      end

      def negate(node)
        Parser::AST::Node.new(:send, [node, :!])
      end

      def nil_node
        Parser::AST::Node.new(:nil, [])
      end
    end
  end
end
