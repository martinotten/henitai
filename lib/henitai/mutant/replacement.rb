# frozen_string_literal: true

require "unparser"

module Henitai
  class Mutant
    # Renders the source text spliced in place of a mutant's original node.
    #
    # The text replaces only the original node's range, so it must parse as
    # one expression wherever it lands. An operator expression such as
    # `a || b` does not: spliced into `a && b && c` it reads as
    # `a || (b && c)`. Operator expressions are therefore parenthesised;
    # parentheses never change an expression's meaning, missing ones can. An
    # unmutated control keeps the original text.
    class Replacement
      OPERATOR_METHODS = %i[
        + - * / % ** == != < > <= >= <=> === =~ !~ << >> & | ^ ! ~ -@ +@
      ].freeze

      def self.render(mutant, original_range)
        new(mutant, original_range).render
      end

      def initialize(mutant, original_range)
        @mutant = mutant
        @original_range = original_range
      end

      def render
        return @original_range.source if @mutant.mutated_node.equal?(@mutant.original_node)

        text = unparse(@mutant.mutated_node)
        operator_expression?(@mutant.mutated_node) ? "(#{text})" : text
      end

      private

      def unparse(node)
        Unparser.unparse(node)
      rescue StandardError => e
        raise Unparser::UnsupportedNodeError, e.message
      end

      def operator_expression?(node)
        return false unless node.is_a?(Parser::AST::Node)
        return true if %i[and or].include?(node.type)

        %i[send csend].include?(node.type) && OPERATOR_METHODS.include?(node.children[1])
      end
    end
  end
end
