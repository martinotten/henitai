# frozen_string_literal: true

module Henitai
  # Base class for all mutation operators.
  #
  # An Operator receives an AST node and produces zero or more Mutant objects.
  # Operator names follow the Stryker-compatible naming convention so that the
  # JSON report is compatible with stryker-dashboard filters and HTML reports.
  #
  # Built-in operators (light set):
  #   ArithmeticOperator, EqualityOperator, LogicalOperator, BooleanLiteral,
  #   ConditionalExpression, StringLiteral, ReturnValue
  #
  # Additional operators (full set):
  #   ArrayDeclaration, HashLiteral, RangeLiteral, SafeNavigation,
  #   PatternMatch, BlockStatement, MethodExpression, AssignmentExpression
  #
  # Each operator subclass must implement:
  #   - .node_types  → Array<Symbol>  AST node types this operator handles
  #   - #mutate(node, subject:) → Array<Mutant>
  class Operator
    LIGHT_SET = %w[
      ArithmeticOperator
      EqualityOperator
      LogicalOperator
      BooleanLiteral
      ConditionalExpression
      StringLiteral
      ReturnValue
    ].freeze

    FULL_SET = (LIGHT_SET + %w[
      ArrayDeclaration
      HashLiteral
      RangeLiteral
      SafeNavigation
      PatternMatch
      BlockStatement
      MethodExpression
      AssignmentExpression
    ]).freeze

    # @param set [Symbol] :light or :full
    # @return [Array<Class>] operator classes for the given set
    def self.for_set(set)
      names = set.to_sym == :full ? FULL_SET : LIGHT_SET
      names.map { |name| Henitai::Operators.const_get(name) }
    end

    # Subclasses must declare which AST node types they handle.
    def self.node_types
      raise NotImplementedError, "#{name}.node_types must be defined"
    end

    # @param node    [Parser::AST::Node]
    # @param subject [Subject]
    # @return [Array<Mutant>]
    def mutate(node, subject:)
      raise NotImplementedError, "#{self.class}#mutate must be implemented"
    end

    # Operator name as used in the Stryker JSON schema.
    def name
      self.class.name.split("::").last
    end

    private

    def build_mutant(subject:, original_node:, mutated_node:, description:)
      loc = node_location(original_node)
      Mutant.new(
        subject:,
        operator: name,
        nodes: {
          original: original_node,
          mutated: mutated_node
        },
        description:,
        location: loc
      )
    end

    def node_location(node)
      exp = node.location.expression
      return {} unless exp

      {
        file: exp.source_buffer.name,
        start_line: exp.line,
        end_line: exp.last_line,
        start_col: exp.column,
        end_col: exp.last_column
      }
    end
  end
end
