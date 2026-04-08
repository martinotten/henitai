# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Mutates regular expression literals by altering quantifiers, anchors,
    # and character-class negation.
    #
    # Each applicable transformation yields a separate mutant. Invalid
    # results (unparseable regex) are discarded before emission.
    class RegexMutator < Henitai::Operator
      NODE_TYPES = %i[regexp].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        source, opts_node = extract_parts(node)
        return [] unless source

        transformations(source).filter_map do |new_source, description|
          build_regex_mutant(node, opts_node, new_source, source, description, subject:)
        end
      end

      private

      def extract_parts(node)
        str_child  = node.children.find { |c| c.is_a?(Parser::AST::Node) && c.type == :str }
        opts_node  = node.children.find { |c| c.is_a?(Parser::AST::Node) && c.type == :regopt }
        return nil unless str_child

        [str_child.children[0], opts_node]
      end

      def build_regex_mutant(node, opts_node, new_source, original, description, subject:) # rubocop:disable Metrics/ParameterLists
        return if new_source == original
        return unless valid_regex?(new_source)

        children = [Parser::AST::Node.new(:str, [new_source]), opts_node]
        mutated = Parser::AST::Node.new(:regexp, children)
        build_mutant(subject:, original_node: node, mutated_node: mutated, description:)
      end

      def transformations(source)
        [
          *quantifier_swaps(source),
          *anchor_removals(source),
          *char_class_negations(source)
        ]
      end

      def quantifier_swaps(source)
        [
          [source.gsub(/(?<=[^*+?\\])\+/, "*"), "replaced + quantifier with *"],
          [source.gsub(/(?<=[^*+?\\])\*/, "+"), "replaced * quantifier with +"]
        ]
      end

      def anchor_removals(source)
        [
          [source.sub("^", ""), "removed ^ anchor"],
          [source.sub(/\$$/, ""), "removed $ anchor"]
        ]
      end

      def char_class_negations(source)
        [[source.gsub(/\[(?!\^)/, "[^"), "negated character class"]]
      end

      def valid_regex?(source)
        Regexp.new(source)
        true
      rescue RegexpError
        false
      end
    end
  end
end
