# frozen_string_literal: true

require "parser/current"

# rubocop:disable Lint/BooleanSymbol, Style/MultilineIfModifier, Layout/MultilineOperationIndentation, Layout/HashAlignment
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

        mutations.concat(removed_else_branch(node, subject:, then_branch:)) if then_branch &&
          else_branch
        mutations.concat(
          removed_then_branch(node, subject:, else_branch:)
        ) if then_branch

        mutations
      end

      def mutate_case(node, subject:)
        condition = node.children.first
        when_nodes, else_branch = case_children(node.children.drop(1))
        mutations = condition_variants(node, subject:, condition:)

        mutations.concat(case_when_mutants(subject:, node:, when_nodes:))

        if else_branch
          mutations << branch_mutant(
            subject:,
            node:,
            replacement: else_branch,
            description: "kept else branch"
          )
        end

        mutations
      end

      def mutate_loop(node, subject:)
        condition = node.children.first
        condition_variants(node, subject:, condition:)
      end

      def case_when_mutants(subject:, node:, when_nodes:)
        when_nodes.map do |when_node|
          branch_mutant(
            subject:,
            node:,
            replacement: when_node.children.last || nil_node,
            description: "kept when branch"
          )
        end
      end

      def case_children(children)
        return [[], nil] if children.empty?

        if children.last&.type == :when
          [children, nil]
        else
          [children[0...-1], children.last]
        end
      end

      def condition_variants(node, subject:, condition:)
        [
          condition_mutant(node, subject:, replacement: true_node,
            description: "replaced condition with true"),
          condition_mutant(node, subject:, replacement: false_node,
            description: "replaced condition with false"),
          condition_mutant(node, subject:, replacement: negate(condition),
            description: "negated condition")
        ]
      end

      def condition_mutant(node, subject:, replacement:, description:)
        branch_mutant(
          subject:,
          node:,
          replacement: with_condition(node, replacement),
          description:
        )
      end

      def removed_else_branch(node, subject:, then_branch:)
        [
          branch_mutant(
            subject:,
            node:,
            replacement: then_branch,
            description: "removed else branch"
          )
        ]
      end

      def removed_then_branch(node, subject:, else_branch:)
        [
          branch_mutant(
            subject:,
            node:,
            replacement: else_branch || nil_node,
            description: "removed then branch"
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

      def true_node
        Parser::AST::Node.new(:true, [])
      end

      def false_node
        Parser::AST::Node.new(:false, [])
      end

      def nil_node
        Parser::AST::Node.new(:nil, [])
      end
    end
  end
end
# rubocop:enable Lint/BooleanSymbol, Style/MultilineIfModifier, Layout/MultilineOperationIndentation, Layout/HashAlignment
