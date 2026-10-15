# frozen_string_literal: true

require_relative "../parser_current"
require_relative "regex_metacharacters"

module Henitai
  module Operators
    # Mutates regular expression literals by altering quantifiers, anchors,
    # and character-class negation.
    #
    # Each applicable transformation yields a separate mutant. Invalid
    # results (unparseable regex) are discarded before emission. Only static,
    # single-segment literals are mutated: an interpolated or multi-line
    # regexp is split into several parts, and rewriting one part alone would
    # drop or misread the others.
    # Anchor removal and character-class negation are intentionally one-way:
    # they reduce noisy patterns rather than mirroring a full edit matrix.
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
        *parts, opts_node = node.children
        return unless opts_node.is_a?(Parser::AST::Node) && opts_node.type == :regopt
        return unless parts.size == 1 && parts.first.is_a?(Parser::AST::Node) && parts.first.type == :str

        [parts.first.children[0], opts_node]
      end

      def build_regex_mutant(node, opts_node, new_source, original, description, subject:) # rubocop:disable Metrics/ParameterLists
        return if new_source == original
        return unless valid_regex?(new_source)

        children = [Parser::AST::Node.new(:str, [new_source]), opts_node]
        mutated = Parser::AST::Node.new(:regexp, children)
        build_mutant(subject:, original_node: node, mutated_node: mutated, description:)
      end

      def transformations(source)
        found = RegexMetacharacters.new(source)
        [
          [edit(source, found.quantifiers("+"), "*"), "replaced + quantifier with *"],
          [edit(source, found.quantifiers("*"), "+"), "replaced * quantifier with +"],
          # Anchors are removed, never added, and character classes are only
          # negated: the reverse edits would just recreate an input.
          [edit(source, found.anchors("^").first(1), ""), "removed ^ anchor"],
          [edit(source, found.anchors("$").last(1), ""), "removed $ anchor"],
          [insert_after(source, found.class_openers, "^"), "negated character class"]
        ]
      end

      # Replaces the single characters at +indices+, from the last to the
      # first so earlier indices stay valid.
      def edit(source, indices, text)
        indices.sort.reverse.each_with_object(source.dup) { |index, result| result[index] = text }
      end

      def insert_after(source, indices, text)
        indices.sort.reverse.each_with_object(source.dup) { |index, result| result.insert(index + 1, text) }
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
