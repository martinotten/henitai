# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Replaces return values and implicit final expressions with neutral values.
    class ReturnValue < Henitai::Operator
      # Parser uses :true / :false node types, so the AST symbols are intentional.
      # rubocop:disable Lint/BooleanSymbol
      NODE_TYPES = %i[return send int float str dstr true false if case while until array hash].freeze
      REPLACEMENT_FACTORIES = [
        -> { Parser::AST::Node.new(:nil, []) },
        -> { Parser::AST::Node.new(:int, [0]) },
        -> { Parser::AST::Node.new(:false, []) }
      ].freeze
      # rubocop:enable Lint/BooleanSymbol

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        case node.type
        when :return
          mutate_explicit_return(node, subject:)
        else
          mutate_implicit_return(node, subject:)
        end
      end

      private

      def mutate_explicit_return(node, subject:)
        expression = node.children.first
        return [] unless expression
        return [] if expression.type == :nil

        replacement_nodes(expression).map do |replacement|
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: Parser::AST::Node.new(:return, [replacement]),
            description: "replaced return value with #{replacement_label(replacement)}"
          )
        end
      end

      def mutate_implicit_return(node, subject:)
        return [] unless node == final_expression_node(subject&.ast_node)

        replacement_nodes(node).map do |replacement|
          build_mutant(
            subject:,
            original_node: node,
            mutated_node: replacement,
            description: "replaced final expression with #{replacement_label(replacement)}"
          )
        end
      end

      def final_expression_node(method_node)
        return unless method_node

        body = method_node.children.last
        return body unless body&.type == :begin

        body.children.rfind { |child| child.is_a?(Parser::AST::Node) }
      end

      # rubocop:disable Lint/BooleanSymbol
      def replacement_nodes(node)
        nodes = REPLACEMENT_FACTORIES.map(&:call)

        case node.type
        when :true
          nodes << Parser::AST::Node.new(:false, [])
        when :false
          nodes.delete_if { |replacement| replacement.type == :false }
          nodes << Parser::AST::Node.new(:true, [])
        end

        nodes
          .uniq { |replacement| [replacement.type, replacement.children] }
          .reject { |replacement| replacement == node }
      end

      def replacement_label(node)
        case node.type
        when :nil
          "nil"
        when :false
          "false"
        when :true
          "true"
        when :int
          node.children.first.to_s
        else
          node.type.to_s
        end
      end
      # rubocop:enable Lint/BooleanSymbol
    end
  end
end
