# frozen_string_literal: true

require_relative "../parser_current"

module Henitai
  module Operators
    # Reduces hash literals: empties the whole hash and removes one pair at a
    # time. Symbol-key -> string-key mutation lives in {HashKeyType} (hard
    # set) because framework key normalization makes it frequently unkillable
    # (ADR-12).
    class HashLiteral < Henitai::Operator
      NODE_TYPES = [:hash].freeze

      # Key node types whose first child is the literal value itself.
      SCALAR_KEY_TYPES = %i[sym int float].freeze
      # Same, but rendered quoted so a string key stays distinguishable from
      # the symbol key of the same name.
      QUOTED_KEY_TYPES = [:str].freeze
      # Keyword literals carry no children; the node type is the label.
      KEYWORD_KEY_TYPES = %i[true false nil].freeze

      def self.node_types
        NODE_TYPES
      end

      def mutate(node, subject:)
        return [] if node.children.empty?

        mutants = [empty_hash_mutant(node, subject:)]
        mutants.concat(pair_removal_mutants(node, subject:))
        mutants
      end

      private

      def empty_hash_mutant(node, subject:)
        build_mutant(
          subject:,
          original_node: node,
          mutated_node: Parser::AST::Node.new(:hash, []),
          description: "replaced hash with empty hash"
        )
      end

      # Removing the only entry would duplicate the empty-hash mutant.
      def pair_removal_mutants(node, subject:)
        return [] if node.children.size < 2

        node.children.each_with_index.filter_map do |pair, index|
          next unless pair.type == :pair

          build_mutant(
            subject:,
            original_node: node,
            mutated_node: hash_without_pair(node, index),
            description: "removed hash pair #{pair_key_label(pair, index)}"
          )
        end
      end

      def hash_without_pair(node, pair_index)
        remaining = node.children.reject.with_index { |_pair, index| index == pair_index }
        Parser::AST::Node.new(:hash, remaining)
      end

      # Only literal keys have a meaningful name. Anything else — a variable,
      # a method call, an array, a nested hash, an interpolated symbol — falls
      # back to its position: rendering those nodes would put a raw
      # s-expression (and, for a nested hash, embedded newlines) into every
      # report surface and into MutantIdentity.stable_id.
      def pair_key_label(pair, index)
        label = literal_key_label(pair.children.first)
        return "##{index + 1}" if label.nil? || label.include?("\n")

        label
      end

      # A symbol can itself contain a newline (`:"a\nb"`), which would put the
      # break straight back into every single-line surface — hence the
      # newline check on the rendered label above, not just on the node type.
      def literal_key_label(key)
        case key.type
        when *SCALAR_KEY_TYPES then key.children.first.to_s
        when *QUOTED_KEY_TYPES then key.children.first.inspect
        when *KEYWORD_KEY_TYPES then key.type.to_s
        end
      end
    end
  end
end
